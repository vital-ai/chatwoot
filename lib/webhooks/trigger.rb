class Webhooks::Trigger
  SUPPORTED_ERROR_HANDLE_EVENTS = %w[message_created message_updated].freeze

  def initialize(url, payload, webhook_type)
    @url = url
    @payload = payload
    @webhook_type = webhook_type
  end

  def self.execute(url, payload, webhook_type)
    new(url, payload, webhook_type).execute
  end

  def execute
    perform_request
  rescue StandardError => e
    handle_error(e)
    Rails.logger.warn "Exception: Invalid webhook URL #{@url} : #{e.message}"
  end

  private

  def perform_request
    timestamp = Time.current.to_i
    signature = generate_signature(timestamp) if bot_webhook_with_signatures?
    
    headers = { content_type: :json, accept: :json }
    headers.merge!(signature_headers(signature, timestamp)) if signature
    
    RestClient::Request.execute(
      method: :post,
      url: @url,
      payload: @payload.to_json,
      headers: headers,
      timeout: 5
    )
  end

  def handle_error(error)
    return unless should_handle_error?
    return unless message

    update_message_status(error)
  end

  def should_handle_error?
    @webhook_type == :api_inbox_webhook && SUPPORTED_ERROR_HANDLE_EVENTS.include?(@payload[:event])
  end

  def update_message_status(error)
    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  end

  def message
    return if message_id.blank?

    @message ||= Message.find_by(id: message_id)
  end

  def message_id
    @payload[:id]
  end

  def bot_webhook_with_signatures?
    bot_webhook? && Webhooks::SignatureService.enabled?
  end

  def bot_webhook?
    @webhook_type == :agent_bot_webhook
  end

  def generate_signature(timestamp)
    return nil unless bot_webhook_with_signatures?
    
    begin
      Webhooks::SignatureService.generate(@payload.to_json, timestamp)
    rescue StandardError => e
      Rails.logger.error "Failed to generate webhook signature: #{e.message}"
      nil
    end
  end

  def signature_headers(signature, timestamp)
    return {} unless signature
    
    headers = {
      'X-Chatwoot-Signature' => signature,
      'X-Chatwoot-Timestamp' => timestamp.to_s
    }
    
    # Add bot ID if available in payload
    if @payload[:bot]&.dig(:id)
      headers['X-Chatwoot-Bot-Id'] = @payload[:bot][:id].to_s
    end
    
    headers
  end
end
