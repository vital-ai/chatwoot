class AgentBots::WebhookJob < WebhookJob
  queue_as :high

  def perform(url, payload)
    # Pass agent_bot webhook type to enable signature generation
    Webhooks::Trigger.execute(url, payload, :agent_bot_webhook)
  end
end
