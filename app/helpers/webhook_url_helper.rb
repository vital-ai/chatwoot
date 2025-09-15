module WebhookUrlHelper
  # Returns the base URL for webhook endpoints
  # Uses WEBHOOK_BASE_URL if set, otherwise falls back to FRONTEND_URL
  def webhook_base_url
    ENV.fetch('WEBHOOK_BASE_URL', ENV.fetch('FRONTEND_URL', 'http://localhost:3000'))
  end

  # Constructs a webhook URL for the given path
  # @param path [String] The webhook path (e.g., '/webhooks/sms/123456')
  # @return [String] The full webhook URL
  def webhook_url(path)
    "#{webhook_base_url}#{path}"
  end
end
