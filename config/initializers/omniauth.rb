require 'securerandom'

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2, ENV.fetch('GOOGLE_OAUTH_CLIENT_ID', nil), ENV.fetch('GOOGLE_OAUTH_CLIENT_SECRET', nil), {
    provider_ignores_state: true
  }
  
  # Configuration for Keycloak 17+ (Quarkus) based on user's suggestion
  realm = ENV.fetch('KEYCLOAK_REALM', 'master')
  site_url = ENV.fetch('KEYCLOAK_SERVER_URL', 'http://host.docker.internal:8085')
  callback_url = ENV.fetch('KEYCLOAK_CALLBACK_URL', ENV.fetch('FRONTEND_URL', 'http://localhost:3000') + '/auth/keycloak/callback')
  
  # For logging/debugging
  Rails.logger.info("Configuring Keycloak with:")
  Rails.logger.info("  Site URL: #{site_url}")
  Rails.logger.info("  Realm: #{realm}")
  Rails.logger.info("  Callback URL: #{callback_url}")
  Rails.logger.info("  Discovery path: #{site_url}/realms/#{realm}/.well-known/openid-configuration")
  
  provider :keycloak_openid, 
          ENV.fetch('KEYCLOAK_CLIENT_ID', nil),
          ENV.fetch('KEYCLOAK_CLIENT_SECRET', nil),
          {
            client_options: {
              site: site_url,
              realm: realm,
              # For Keycloak 17+ (Quarkus), set base_url to empty string to remove /auth prefix
              base_url: '',
              authorize_url: '/realms/' + realm + '/protocol/openid-connect/auth',
              token_url: '/realms/' + realm + '/protocol/openid-connect/token',
              userinfo_url: '/realms/' + realm + '/protocol/openid-connect/userinfo'
            },
            # Critical for newer Keycloak: explicitly set discovery path to avoid /auth prefix
            discovery: true,
            discovery_path: "#{site_url}/realms/#{realm}/.well-known/openid-configuration",
            # Explicitly set redirect_uri to ensure consistency
            redirect_uri: callback_url,
            # Use transport_method: :query to send parameters in query string instead of body
            transport_method: :query,
            name: 'keycloak',           # Matches the callback route
            callback_path: '/auth/keycloak/callback', # Explicit callback path
            provider_ignores_state: true, # Similar to Google OAuth config
            scope: 'openid email profile', # Request these scopes
            response_type: 'code',     # Use authorization code flow
            prompt: 'login',           # Force login prompt
            nonce: SecureRandom.hex(16)  # Security nonce
            # Disable PKCE as it's causing issues with the Keycloak server
            # pkce: false
          }
end
