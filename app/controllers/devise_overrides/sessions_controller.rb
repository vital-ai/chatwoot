class DeviseOverrides::SessionsController < DeviseTokenAuth::SessionsController
  # Prevent session parameter from being passed
  # Unpermitted parameter: session
  wrap_parameters format: []
  before_action :process_sso_auth_token, only: [:create]

  def new
    Rails.logger.info "SessionsController#new called. Request path: #{request.path}, Referrer: #{request.referrer}"
    Rails.logger.info "Request parameters: #{params.inspect}"
    Rails.logger.info "OmniAuth env: #{request.env['omniauth.auth'].inspect if request.env['omniauth.auth']}"
    Rails.logger.info "OmniAuth error: #{request.env['omniauth.error'].inspect if request.env['omniauth.error']}"
    
    # If we're in the OmniAuth callback with an error, proceed with error redirect
    if request.env['omniauth.error']
      Rails.logger.error("OmniAuth error detected: #{request.env['omniauth.error'].message}")
      redirect_to login_page_url(error: 'access-denied'), allow_other_host: true
      return
    end
    
    # If this is a regular sign-in page request and SSO is enabled, redirect to Keycloak
    # This enforces SSO by preventing access to the email/password login form
    if ENV.fetch('KEYCLOAK_CLIENT_ID', nil).present?
      Rails.logger.info "Redirecting to Keycloak for SSO authentication"
      redirect_to '/auth/keycloak_openid?resource_class=User', allow_other_host: true
      return
    end
    
    # For non-SSO or if we somehow get here with SSO enabled
    Rails.logger.info "Proceeding with normal Devise sign-in flow"
    super
  end

  def create
    # Authenticate user via the temporary sso auth token
    if params[:sso_auth_token].present? && @resource.present?
      authenticate_resource_with_sso_token
      yield @resource if block_given?
      render_create_success
    else
      super
    end
  end

  def render_create_success
    render partial: 'devise/auth', formats: [:json], locals: { resource: @resource }
  end

  private

  def login_page_url(error: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)

    "#{frontend_url}/app/login?error=#{error}"
  end

  def authenticate_resource_with_sso_token
    @token = @resource.create_token
    @resource.save!

    sign_in(:user, @resource, store: false, bypass: false)
    # invalidate the token after the user is signed in
    @resource.invalidate_sso_auth_token(params[:sso_auth_token])
  end

  def process_sso_auth_token
    return if params[:email].blank?

    user = User.from_email(params[:email])
    @resource = user if user&.valid_sso_auth_token?(params[:sso_auth_token])
  end
end

DeviseOverrides::SessionsController.prepend_mod_with('DeviseOverrides::SessionsController')
