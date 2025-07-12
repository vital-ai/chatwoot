class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  
  def keycloak_openid
    auth = request.env['omniauth.auth']
    Rails.logger.info "Keycloak auth response: #{auth.to_json}"
    
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
