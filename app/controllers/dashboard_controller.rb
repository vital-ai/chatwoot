class DashboardController < ActionController::Base
  include SwitchLocale

  # Check for auth failures first, before redirect_to_keycloak
  before_action :check_auth_failure
  before_action :redirect_to_keycloak, only: [:index]
  
  before_action :set_application_pack
  before_action :set_global_config
  before_action :set_dashboard_scripts
  around_action :switch_locale
  before_action :ensure_installation_onboarding, only: [:index]
  before_action :render_hc_if_custom_domain, only: [:index]
  before_action :ensure_html_format
  layout 'vueapp'

  def index; end

  private

  # New method to check for auth failures before redirect_to_keycloak
  def check_auth_failure
    # Check for auth failure indicators in params or session
    auth_failed = params[:auth_failed].present? || 
                 params[:error].present? || 
                 params[:auth_failure].present? || 
                 (defined?(session) && session[:auth_failed])
    
    if auth_failed
      Rails.logger.info "Auth failure detected: #{params[:auth_failed] || params[:error] || params[:auth_failure]}"
      # Store in session for persistence across redirects
      session[:auth_failed] = true if defined?(session)
      
      # This will prevent infinite redirects on auth failure
      @skip_keycloak_redirect = true
    end
  end

  def redirect_to_keycloak
    # Add detailed debugging
    Rails.logger.info "========== KEYCLOAK REDIRECT DEBUG =========="
    Rails.logger.info "Current user: #{current_user.inspect}" if defined?(current_user)
    Rails.logger.info "Request path: #{request.path}"
    Rails.logger.info "Current controller: #{self.class.name}, action: #{action_name}"
    Rails.logger.info "Request format: #{request.format}"
    Rails.logger.info "Session ID: #{request.session.id}" if defined?(request.session)
    Rails.logger.info "Request params: #{params.inspect}"
    Rails.logger.info "Request env omniauth.auth: #{request.env['omniauth.auth'].inspect}" if request.env['omniauth.auth']
    Rails.logger.info "Request env omniauth.origin: #{request.env['omniauth.origin']}" if request.env['omniauth.origin']
    Rails.logger.info "============================================"
    
    # Do not redirect if we're in a callback or auth flow
    if request.path.include?('/auth/') || 
       request.path.include?('/users/auth/') || 
       request.path.include?('/users/confirmation') ||
       request.path.include?('/api/') ||
       # These are additional OAuth callback indicators:
       request.env['omniauth.auth'].present? ||
       request.env['omniauth.origin'].present? ||
       params[:code].present? || 
       params[:provider].present? ||
       params[:origin].present?
       
      Rails.logger.info "SKIPPING REDIRECT: Path includes auth or API path, or has OAuth callback indicators"
      return
    end
    
    # Skip redirect if auth failure was detected
    if @skip_keycloak_redirect
      Rails.logger.info "SKIPPING REDIRECT: Auth failure flag detected"
      
      # Clear the auth_failed flag after using it
      session[:auth_failed] = nil if defined?(session)
      
      # Explicitly ensure all required variables are set before rendering
      # This prevents NoMethodError and ArgumentError in the layout
      set_global_config if @global_config.nil?
      set_application_pack if @application_pack.nil?
      
      # For auth failure/login pages, we should use the v3app pack
      @application_pack = 'v3app' if request.path.include?('/login')
      
      # Render the index page directly
      return render :index
    end
    
    Rails.logger.info "PERFORMING REDIRECT: Redirecting to Keycloak"

    # Check if user is already authenticated
    if user_signed_in?
      Rails.logger.info "User already signed in, skipping Keycloak redirect"
      return
    end

    # Build the redirect URL with required parameters for DeviseTokenAuth
    # - resource_class=User tells devise_token_auth which model to authenticate against
    # - auth_origin_url is the URL to redirect back to after successful authentication
    redirect_url = '/auth/keycloak_openid?resource_class=User'
    redirect_url += "&auth_origin_url=#{CGI.escape(request.base_url + '/app')}"
    
    # Log the full redirect URL for debugging
    Rails.logger.info "Redirecting to: #{redirect_url}"
    
    # Use an immediate, forced redirect with a status code
    redirect_to redirect_url, status: :found, allow_other_host: true and return
  end

  def ensure_html_format
    render json: { error: 'Please use API routes instead of dashboard routes for JSON requests' }, status: :not_acceptable if request.format.json?
  end

  def set_global_config
    @global_config = GlobalConfig.get(
      'LOGO', 'LOGO_DARK', 'LOGO_THUMBNAIL',
      'INSTALLATION_NAME',
      'WIDGET_BRAND_URL', 'TERMS_URL',
      'BRAND_URL', 'BRAND_NAME',
      'PRIVACY_URL',
      'DISPLAY_MANIFEST',
      'CREATE_NEW_ACCOUNT_FROM_DASHBOARD',
      'CHATWOOT_INBOX_TOKEN',
      'API_CHANNEL_NAME',
      'API_CHANNEL_THUMBNAIL',
      'ANALYTICS_TOKEN',
      'DIRECT_UPLOADS_ENABLED',
      'HCAPTCHA_SITE_KEY',
      'LOGOUT_REDIRECT_LINK',
      'DISABLE_USER_PROFILE_UPDATE',
      'DEPLOYMENT_ENV',
      'INSTALLATION_PRICING_PLAN'
    ).merge(app_config)
  end

  def set_dashboard_scripts
    @dashboard_scripts = sensitive_path? ? nil : GlobalConfig.get_value('DASHBOARD_SCRIPTS')
  end

  def ensure_installation_onboarding
    redirect_to '/installation/onboarding' if ::Redis::Alfred.get(::Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
  end

  def render_hc_if_custom_domain
    domain = request.host
    return if domain == URI.parse(ENV.fetch('FRONTEND_URL', '')).host

    @portal = Portal.find_by(custom_domain: domain)
    return unless @portal

    @locale = @portal.default_locale
    render 'public/api/v1/portals/show', layout: 'portal', portal: @portal and return
  end

  def app_config
    {
      APP_VERSION: Chatwoot.config[:version],
      VAPID_PUBLIC_KEY: VapidService.public_key,
      ENABLE_ACCOUNT_SIGNUP: GlobalConfigService.load('ENABLE_ACCOUNT_SIGNUP', 'false'),
      FB_APP_ID: GlobalConfigService.load('FB_APP_ID', ''),
      INSTAGRAM_APP_ID: GlobalConfigService.load('INSTAGRAM_APP_ID', ''),
      FACEBOOK_API_VERSION: GlobalConfigService.load('FACEBOOK_API_VERSION', 'v17.0'),
      IS_ENTERPRISE: ChatwootApp.enterprise?,
      AZURE_APP_ID: GlobalConfigService.load('AZURE_APP_ID', ''),
      GIT_SHA: GIT_HASH
    }
  end

  def set_application_pack
    @application_pack = if request.path.include?('/auth') || request.path.include?('/login')
                          'v3app'
                        else
                          'dashboard'
                        end
  end

  def sensitive_path?
    # dont load dashboard scripts on sensitive paths like password reset
    sensitive_paths = [edit_user_password_path].freeze

    # remove app prefix
    current_path = request.path.gsub(%r{^/app}, '')

    sensitive_paths.include?(current_path)
  end
end
