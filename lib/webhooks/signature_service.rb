class Webhooks::SignatureService
  class << self
    def generate(payload, timestamp = nil)
      return nil unless webhook_secret_configured?
      
      timestamp ||= Time.current.to_i
      signature_payload = "#{timestamp}.#{payload}"
      signature = OpenSSL::HMAC.hexdigest('SHA256', webhook_secret, signature_payload)
      "sha256=#{signature}"
    end
    
    def verify(payload, signature, timestamp, tolerance = 300)
      return false unless webhook_secret_configured?
      
      expected_signature = generate(payload, timestamp)
      return false unless secure_compare(signature, expected_signature)
      return false if timestamp_expired?(timestamp, tolerance)
      true
    end
    
    def enabled?
      webhook_secret_configured?
    end
    
    private
    
    def webhook_secret
      Rails.application.config.chatwoot_bot_webhook_secret
    end
    
    def webhook_secret_configured?
      webhook_secret.present?
    end
    
    def secure_compare(a, b)
      ActiveSupport::SecurityUtils.secure_compare(a, b)
    end
    
    def timestamp_expired?(timestamp, tolerance)
      Time.current.to_i - timestamp.to_i > tolerance
    end
  end
end
