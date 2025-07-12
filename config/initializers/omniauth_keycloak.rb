# Monkey patch the omniauth-keycloak gem to fix URL issues
# Explicitly mount OmniAuth middleware for Keycloak - only in web processes
if defined?(Rails) && Rails.env
  Rails.application.config.middleware.use OmniAuth::Builder do
    # Using simpler logging to avoid potential issues
    OmniAuth.config.logger = Rails.logger
    
    # Debug log all requests passing through OmniAuth
    OmniAuth.config.logger.level = Logger::DEBUG
    
    # Ensure redirect is handled correctly
    OmniAuth.config.allowed_request_methods = [:post, :get]
    
    # Since we're using Docker, best to use host.docker.internal
    keycloak_server_url = 'http://host.docker.internal:8085'
    keycloak_realm = ENV.fetch('KEYCLOAK_REALM')
    
    # Explicitly set the host for redirect URIs to match what's configured in Keycloak
    OmniAuth.config.full_host = 'http://localhost:3000'
    redirect_uri = "#{OmniAuth.config.full_host}/auth/keycloak_openid/callback"
    
    Rails.logger.info("[OmniAuth] ------------- KEYCLOAK CONFIG -------------")
    Rails.logger.info("[OmniAuth] Setting full_host to: #{OmniAuth.config.full_host}")
    Rails.logger.info("[OmniAuth] Redirect URI: #{redirect_uri}")
    Rails.logger.info("[OmniAuth] Keycloak client_id: #{ENV.fetch('KEYCLOAK_CLIENT_ID')}")
    Rails.logger.info("[OmniAuth] Keycloak realm: #{keycloak_realm}")
    Rails.logger.info("[OmniAuth] Keycloak server_url: #{keycloak_server_url}")
    Rails.logger.info("[OmniAuth] ----------------------------------------")
    
    # Configure OmniAuth error handling
    OmniAuth.config.on_failure = lambda do |env|
      # Log detailed error information
      Rails.logger.error("[OmniAuth] FAILURE: #{env['omniauth.error'].class} - #{env['omniauth.error'].message}")
      Rails.logger.error("[OmniAuth] FAILURE STRATEGY: #{env['omniauth.error.strategy'].name}")
      Rails.logger.error("[OmniAuth] FAILURE PATH_PREFIX: #{OmniAuth.config.path_prefix}")
      
      # Ensure we have the correct Devise mapping
      env['devise.mapping'] = Devise.mappings[:user]
      
      # Get error message
      error_type = env['omniauth.error.type'] || :unknown_error
      error_message = env['omniauth.error.message'] || 'Authentication failed'
      Rails.logger.error("[OmniAuth] Redirecting to login due to: #{error_type} - #{error_message}")
      
      # For invalid_grant errors, redirect directly to login page to prevent loops
      # Check error message directly to avoid class reference issues
      if env['omniauth.error'] && 
         env['omniauth.error'].message && 
         env['omniauth.error'].message.include?('invalid_grant')
        Rails.logger.info("[OmniAuth] Detected invalid_grant error, redirecting to app login directly")
        # Add auth_failed=true parameter to break the redirect loop
        return [302, {'Location' => '/app/login?auth_failed=true', 'Content-Type' => 'text/html'}, ['']]
      end
      
      # Fall back to default Devise failure handling for other errors
      Devise::OmniauthCallbacksController.action(:failure).call(env)
    end
    
    # Log before requests for debugging
    OmniAuth.config.before_request_phase = lambda do |env|
      request = ActionDispatch::Request.new(env)
      Rails.logger.info("[OmniAuth] Starting request phase for: #{request.path}")
      Rails.logger.info("[OmniAuth] Params: #{request.params.inspect}")
    end
    
    # Debug logging
    Rails.logger.info("[OmniAuth] Configuring Keycloak with URL: #{keycloak_server_url}")
    
    # Explicitly set redirect_uri to avoid mismatches
    # Use a hardcoded value to ensure consistency
    redirect_uri = "http://localhost:3000/auth/keycloak_openid/callback"
    Rails.logger.info("[OmniAuth] Setting redirect_uri to: #{redirect_uri}")
    
    # Log critical Keycloak config for debugging
    Rails.logger.info("[OmniAuth] Keycloak client_id: #{ENV.fetch('KEYCLOAK_CLIENT_ID')}")
    Rails.logger.info("[OmniAuth] Keycloak realm: #{keycloak_realm}")
    Rails.logger.info("[OmniAuth] Keycloak server_url: #{keycloak_server_url}")

    # Updated configuration for modern Keycloak (v17+)
    provider :keycloak_openid,
      client_id: ENV.fetch('KEYCLOAK_CLIENT_ID', nil),
      client_secret: ENV.fetch('KEYCLOAK_CLIENT_SECRET', nil),
      realm: ENV.fetch('KEYCLOAK_REALM', nil),
      site: ENV.fetch('KEYCLOAK_SERVER_URL', nil),
      base_url: '',
      discovery: false, # Disable discovery to use explicit URLs
      # Override strategy methods to ensure proper URL handling
      client_options: {
        site: ENV.fetch('KEYCLOAK_SERVER_URL', nil),
        realm: ENV.fetch('KEYCLOAK_REALM', nil),
        auth_scheme: :request_body, # Try using request body instead of header
        token_method: :post,
        # Explicitly set the auth, token, and userinfo URLs
        authorize_url: '/realms/' + ENV.fetch('KEYCLOAK_REALM', 'chatwoot') + '/protocol/openid-connect/auth',
        token_url: '/realms/' + ENV.fetch('KEYCLOAK_REALM', 'chatwoot') + '/protocol/openid-connect/token',
        userinfo_url: '/realms/' + ENV.fetch('KEYCLOAK_REALM', 'chatwoot') + '/protocol/openid-connect/userinfo'
      },
      # Explicitly set redirect URI - always use localhost instead of 0.0.0.0
      redirect_uri: (Rails.env.production? ? ENV.fetch('FRONTEND_URL', nil) : nil) || 'http://localhost:3000/auth/keycloak_openid/callback',
      # Override OmniAuth full_host to ensure localhost is used
      full_host: 'http://localhost:3000',
      transport_method: :query,
      provider_ignores_state: true,
      # Disable PKCE - not required per Keycloak settings
      pkce: false,
      name: 'keycloak_openid'
  end
end
