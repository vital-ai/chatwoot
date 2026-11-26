class Twilio::DeliveryStatusController < ApplicationController
  include WebhookUrlHelper
  include TwilioMessagingSignatureVerification

  def create
    Webhooks::TwilioDeliveryStatusJob.perform_later(permitted_params.to_unsafe_hash)

    head :no_content
  end

  private

  def twilio_channel
    Twilio::DeliveryStatusService.find_channel(permitted_params)
  end

  # The URL Twilio was given and signs: on WEBHOOK_BASE_URL (Vital's fork), not FRONTEND_URL.
  def twilio_webhook_url
    webhook_url('/twilio/delivery_status')
  end

  def permitted_params
    params.permit(
      :AccountSid,
      :From,
      :MessageSid,
      :MessagingServiceSid,
      :MessageStatus,
      :ErrorCode,
      :ErrorMessage
    )
  end
end
