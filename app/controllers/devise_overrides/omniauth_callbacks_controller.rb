class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  
  # Handler for the default OmniAuth Keycloak strategy
  def keycloak_openid
    Rails.logger.info "In keycloak_openid callback handler"
    handle_auth_callback
  end

  # Handler for our custom OmniAuth Keycloak strategy
  def custom_keycloak_openid
    Rails.logger.info "In custom_keycloak_openid callback handler"
    handle_auth_callback
  end

  private

  # Common authentication callback handling logic
  def handle_auth_callback
    auth = request.env['omniauth.auth']
    
    # Simple, safer debugging
    Rails.logger.info "Starting OmniAuth callback processing"
    Rails.logger.info "Keycloak auth object present: #{!auth.nil?}"
    
    if auth
      begin
        Rails.logger.info "Keycloak auth response: #{auth.to_json}"
      rescue => e
        Rails.logger.info "Could not convert auth to JSON: #{e.message}"
      end
    end
    
    @resource = User.from_omniauth(auth)
    Rails.logger.info "User resource: #{@resource.persisted? ? 'persisted' : 'not persisted'}"

    if @resource.persisted?
      sign_in_and_redirect @resource, event: :authentication
      Rails.logger.info "User signed in successfully"
    else
      session['devise.keycloak_data'] = auth.except('extra')
      Rails.logger.info "User not persisted, redirecting to registration"
      redirect_to new_user_registration_url
    end
  end
end

