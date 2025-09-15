require 'rails_helper'

RSpec.describe Webhooks::SignatureService do
  let(:payload) { '{"message":"test","event":"message_created"}' }
  let(:timestamp) { 1634567890 }
  let(:webhook_secret) { 'test_secret_key' }

  before do
    allow(Rails.application.config).to receive(:chatwoot_bot_webhook_secret).and_return(webhook_secret)
  end

  describe '.generate' do
    context 'when webhook secret is configured' do
      it 'generates a valid HMAC signature' do
        signature = described_class.generate(payload, timestamp)
        
        expect(signature).to start_with('sha256=')
        expect(signature.length).to eq(71) # 'sha256=' + 64 hex chars
      end

      it 'generates consistent signatures for same input' do
        signature1 = described_class.generate(payload, timestamp)
        signature2 = described_class.generate(payload, timestamp)
        
        expect(signature1).to eq(signature2)
      end

      it 'generates different signatures for different payloads' do
        signature1 = described_class.generate(payload, timestamp)
        signature2 = described_class.generate('{"different":"payload"}', timestamp)
        
        expect(signature1).not_to eq(signature2)
      end

      it 'generates different signatures for different timestamps' do
        signature1 = described_class.generate(payload, timestamp)
        signature2 = described_class.generate(payload, timestamp + 1)
        
        expect(signature1).not_to eq(signature2)
      end

      it 'uses current timestamp when not provided' do
        freeze_time do
          current_timestamp = Time.current.to_i
          signature_with_current = described_class.generate(payload)
          signature_with_explicit = described_class.generate(payload, current_timestamp)
          
          expect(signature_with_current).to eq(signature_with_explicit)
        end
      end
    end

    context 'when webhook secret is not configured' do
      before do
        allow(Rails.application.config).to receive(:chatwoot_bot_webhook_secret).and_return(nil)
      end

      it 'returns nil' do
        signature = described_class.generate(payload, timestamp)
        expect(signature).to be_nil
      end
    end
  end

  describe '.verify' do
    let(:valid_signature) { described_class.generate(payload, timestamp) }

    context 'when webhook secret is configured' do
      it 'verifies valid signatures' do
        result = described_class.verify(payload, valid_signature, timestamp)
        expect(result).to be true
      end

      it 'rejects invalid signatures' do
        invalid_signature = 'sha256=invalid_signature'
        result = described_class.verify(payload, invalid_signature, timestamp)
        expect(result).to be false
      end

      it 'rejects signatures with wrong payload' do
        wrong_payload = '{"wrong":"payload"}'
        result = described_class.verify(wrong_payload, valid_signature, timestamp)
        expect(result).to be false
      end

      it 'rejects expired timestamps' do
        old_timestamp = timestamp - 400 # 400 seconds ago (> 300 second tolerance)
        old_signature = described_class.generate(payload, old_timestamp)
        
        result = described_class.verify(payload, old_signature, old_timestamp)
        expect(result).to be false
      end

      it 'accepts timestamps within tolerance' do
        recent_timestamp = timestamp - 200 # 200 seconds ago (< 300 second tolerance)
        recent_signature = described_class.generate(payload, recent_timestamp)
        
        freeze_time(Time.at(timestamp)) do
          result = described_class.verify(payload, recent_signature, recent_timestamp)
          expect(result).to be true
        end
      end

      it 'accepts custom tolerance' do
        old_timestamp = timestamp - 600 # 600 seconds ago
        old_signature = described_class.generate(payload, old_timestamp)
        
        freeze_time(Time.at(timestamp)) do
          # Should fail with default tolerance (300s)
          result_default = described_class.verify(payload, old_signature, old_timestamp)
          expect(result_default).to be false
          
          # Should pass with custom tolerance (700s)
          result_custom = described_class.verify(payload, old_signature, old_timestamp, 700)
          expect(result_custom).to be true
        end
      end
    end

    context 'when webhook secret is not configured' do
      before do
        allow(Rails.application.config).to receive(:chatwoot_bot_webhook_secret).and_return(nil)
      end

      it 'returns false' do
        result = described_class.verify(payload, 'any_signature', timestamp)
        expect(result).to be false
      end
    end
  end

  describe '.enabled?' do
    context 'when webhook secret is configured' do
      it 'returns true' do
        expect(described_class.enabled?).to be true
      end
    end

    context 'when webhook secret is not configured' do
      before do
        allow(Rails.application.config).to receive(:chatwoot_bot_webhook_secret).and_return('')
      end

      it 'returns false' do
        expect(described_class.enabled?).to be false
      end
    end
  end

  describe 'integration with OpenSSL::HMAC' do
    it 'generates signatures compatible with manual HMAC calculation' do
      signature = described_class.generate(payload, timestamp)
      signature_hex = signature.gsub('sha256=', '')
      
      expected_signature = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, "#{timestamp}.#{payload}")
      
      expect(signature_hex).to eq(expected_signature)
    end
  end
end
