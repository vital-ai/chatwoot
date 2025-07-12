# Simple patch to fix the userinfo_url issue in OmniAuth Keycloak strategy
require 'omniauth-keycloak'

# Monkey-patch the OAuth2::Client class to add the missing userinfo_url method
class OAuth2::Client
  def userinfo_url
    site = options[:site]
    realm = options[:realm]
    # Construct the proper userinfo URL for Keycloak
    "#{site}/realms/#{realm}/protocol/openid-connect/userinfo"
  end
end

if defined?(Rails) && Rails.env
  Rails.application.config.middleware.use OmniAuth::Builder do
    # Using simpler logging to avoid potential issues
    OmniAuth.config.logger = Rails.logger
    
    # Debug log all requests passing through OmniAuth
    OmniAuth.config.logger.level = Logger::DEBUG
    
    # Allow both GET and POST for OmniAuth - required for redirects
    OmniAuth.config.allowed_request_methods = [:post, :get]
    
    # Silence the warning about GET requests
    OmniAuth.config.silence_get_warning = true
    
    # Since we're using Docker, best to use host.docker.internal
    keycloak_server_url = 'http://host.docker.internal:8085'
    keycloak_realm = ENV.fetch('KEYCLOAK_REALM')
    
    # Explicitly set the host for redirect URIs to match what's configured in Keycloak
    OmniAuth.config.full_host = 'http://localhost:3000'
    redirect_uri = "#{OmniAuth.config.full_host}/auth/keycloak_openid/callback"
    
    Rails.logger.info("[OmniAuth] ------------- KEYCLOAK CONFIG -------------")
    Rails.logger.info("[OmniAuth] Using custom Keycloak strategy")
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
    
    # Log before requests for debugging and clean up callback URL
    OmniAuth.config.before_request_phase = lambda do |env|
      request = ActionDispatch::Request.new(env)
      Rails.logger.info("[OmniAuth] Starting request phase for: #{request.path}")
      Rails.logger.info("[OmniAuth] Params: #{request.params.inspect}")
      
      # Clean up callback URL by removing query parameters
      strategy = env['omniauth.strategy']
      if strategy && strategy.respond_to?(:callback_url)
        # Store original method
        unless strategy.class.method_defined?(:original_callback_url)
          strategy.class.send(:alias_method, :original_callback_url, :callback_url)
          
          # Override callback_url to strip query parameters
          strategy.class.send(:define_method, :callback_url) do
            url = original_callback_url
            # Strip query parameters to match Keycloak config
            clean_url = url.split('?').first
            Rails.logger.info("[OmniAuth] Clean callback URL: #{clean_url}")
            clean_url
          end
        end
      end
    end
    
    # Debug logging
    Rails.logger.info("[OmniAuth] Configuring Keycloak with URL: #{keycloak_server_url}")
    
    # Explicitly set redirect_uri to avoid mismatches
    # Use a hardcoded value to ensure consistency - must match Keycloak exactly
    redirect_uri = "http://localhost:3000/auth/keycloak_openid/callback"
    Rails.logger.info("[OmniAuth] Setting redirect_uri to: #{redirect_uri}")
    
    # Log critical Keycloak config for debugging
    Rails.logger.info("[OmniAuth] Keycloak client_id: #{ENV.fetch('KEYCLOAK_CLIENT_ID')}")
    Rails.logger.info("[OmniAuth] Keycloak realm: #{keycloak_realm}")
    Rails.logger.info("[OmniAuth] Keycloak server_url: #{keycloak_server_url}")

    # Configure the standard Keycloak strategy with our patched OAuth2::Client
    provider :keycloak_openid,
      client_id: ENV.fetch('KEYCLOAK_CLIENT_ID', nil),
      client_secret: ENV.fetch('KEYCLOAK_CLIENT_SECRET', nil),
      realm: keycloak_realm,
      site: keycloak_server_url,
      client_options: {
        site: keycloak_server_url,
        realm: keycloak_realm, # Important: pass the realm to the client options for our patch to work
        auth_scheme: :request_body,
        token_method: :post,
        # These URLs are automatically constructed from site and realm
        authorize_url: '/realms/' + keycloak_realm + '/protocol/openid-connect/auth',
        token_url: '/realms/' + keycloak_realm + '/protocol/openid-connect/token',
        # userinfo_url is handled by our patch
      },
      # Make sure redirect URI is correct - must match EXACTLY what's configured in Keycloak client
      redirect_uri: redirect_uri,
      full_host: 'http://localhost:3000',
      provider_ignores_state: true,
      debug: true
  end
end
