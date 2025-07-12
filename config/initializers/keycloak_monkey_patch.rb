# Monkey-patch for OmniAuth Keycloak Strategy to debug token exchange and fix URLs
begin
  # Only apply the patch if the strategy class is already loaded
  if defined?(OmniAuth::Strategies::KeycloakOpenId)
    Rails.logger.info("[KeycloakDebug] Applying monkey patch to OmniAuth::Strategies::KeycloakOpenId")
    
    module OmniAuth
      module Strategies
        class KeycloakOpenId
          # Store original methods for fallback
          alias_method :original_build_access_token, :build_access_token if method_defined?(:build_access_token)
          alias_method :original_client, :client if method_defined?(:client)
          
          # Override client method to ensure proper URLs
          def client
            # Get the client from the original method
            orig_client = original_client
            
            # Get the Keycloak realm from options
            realm = options[:realm] || ENV.fetch('KEYCLOAK_REALM', 'chatwoot')
            
            # Explicitly set the authorization, token and userinfo URLs
            orig_client.options[:authorize_url] = "/realms/#{realm}/protocol/openid-connect/auth"
            orig_client.options[:token_url] = "/realms/#{realm}/protocol/openid-connect/token"
            orig_client.options[:userinfo_url] = "/realms/#{realm}/protocol/openid-connect/userinfo"
            
            # Log the URLs for debugging
            Rails.logger.info("[KeycloakDebug] Authorization URL: #{orig_client.authorize_url}")
            Rails.logger.info("[KeycloakDebug] Token URL: #{orig_client.token_url}")
            Rails.logger.info("[KeycloakDebug] Userinfo URL: #{orig_client.userinfo_url}")
            
            orig_client
          end
          
          def build_access_token
            begin
              Rails.logger.info("[KeycloakDebug] Building access token...")
              Rails.logger.info("[KeycloakDebug] Request params: #{request.params.inspect}")
              Rails.logger.info("[KeycloakDebug] Callback URL: #{callback_url}")
              Rails.logger.info("[KeycloakDebug] Redirect URI: #{options[:redirect_uri] || callback_url}")
              Rails.logger.info("[KeycloakDebug] Client ID: #{client.id}")
              
              # Use token_params method with fallback for compatibility
              params = respond_to?(:token_params) ? token_params : {}
              Rails.logger.info("[KeycloakDebug] Initial token params: #{params.inspect}")
              
              # Build complete token params
              token_params = {
                'client_id' => client.id,
                'client_secret' => client.secret,
                'code' => request.params['code'],
                'grant_type' => 'authorization_code',
                'redirect_uri' => options[:redirect_uri] || callback_url
              }.merge(params)
              
              # Explicitly log token URL and request details
              token_url = client.token_url
              Rails.logger.info("[KeycloakDebug] Token URL: #{token_url}")
              Rails.logger.info("[KeycloakDebug] Full token params: #{token_params.inspect}")
              
              begin
                # Make sure we have the correct OAuth2 Error class loaded
                require 'oauth2'
                
                # Get the token directly with verbose error handling
                response = client.get_token(token_params)
                Rails.logger.info("[KeycloakDebug] Token response successful")
                return response
              rescue ::OAuth2::Error => e
                Rails.logger.error("[KeycloakDebug] OAuth2 Error during token request: #{e.message}")
                if e.response && e.response.body
                  Rails.logger.error("[KeycloakDebug] Response body: #{e.response.body}")
                end
                raise e
              rescue => e
                Rails.logger.error("[KeycloakDebug] Unexpected error during token request: #{e.class} - #{e.message}")
                raise e
              end
            rescue => e
              Rails.logger.error("[KeycloakDebug] Exception in patched build_access_token: #{e.class} - #{e.message}")
              Rails.logger.error("[KeycloakDebug] Backtrace: #{e.backtrace.join("\n")}")
              raise e
            end
          end
        end
      end
    end
  else
    Rails.logger.warn("[KeycloakDebug] OmniAuth::Strategies::KeycloakOpenId not loaded yet, skipping monkey patch")
  end
rescue => e
  Rails.logger.error("[KeycloakDebug] Error applying monkey patch: #{e.class} - #{e.message}")
end
