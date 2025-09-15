Rails.application.configure do
  # Bot webhook signature secret configuration
  config.chatwoot_bot_webhook_secret = ENV['CHATWOOT_BOT_WEBHOOK_SECRET']
  
  # Log warning if webhook secret is not configured in production
  if Rails.env.production? && config.chatwoot_bot_webhook_secret.blank?
    Rails.logger.warn "CHATWOOT_BOT_WEBHOOK_SECRET is not configured. Bot webhook signatures will be disabled."
  end
end
