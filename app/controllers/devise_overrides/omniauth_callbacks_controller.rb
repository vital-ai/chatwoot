class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  
  # Override auth_hash getter to ensure we always have valid data
  def auth_hash
    # Get the auth_hash from super or fall back to omniauth.auth
    @auth_hash ||= begin
      # Try to get from parent class
      hash = super
      
      # If nil, create from request env
      if hash.nil?
        Rails.logger.info "=== DEBUG: Creating auth_hash from omniauth.auth ==="
        raw_auth = request.env['omniauth.auth']
        
        if raw_auth
          # Log key auth data for debugging
          Rails.logger.info "Auth data found in request.env['omniauth.auth']"
          Rails.logger.info "Auth UID: #{raw_auth['uid']}" if raw_auth['uid']
          Rails.logger.info "Auth provider: #{raw_auth['provider']}" if raw_auth['provider']
          Rails.logger.info "Auth email: #{raw_auth.dig('info', 'email')}" if raw_auth['info']
          
          # Return the raw_auth as is - don't modify the structure as DeviseTokenAuth expects
          # the OmniAuth::AuthHash format, not a regular hash
          hash = raw_auth
        else
          # Create minimal hash with data from params if we can't find auth data
          Rails.logger.warn "No auth data in omniauth.auth, creating minimal hash from params"
          hash = OmniAuth::AuthHash.new(
            'uid' => params['code'] || SecureRandom.uuid,
            'provider' => params['provider'] || 'keycloak_openid',
            'info' => { 'email' => nil, 'name' => nil }
          )
        end
      end
      
      hash
    end
  end
  
  # Override the get_resource_from_auth_hash method to debug the process
  def get_resource_from_auth_hash
    Rails.logger.info "=== DEBUG: Getting resource from auth hash ==="
    
    # Log current auth_hash state
    current_hash = auth_hash
    
    if current_hash
      Rails.logger.info "Auth hash class: #{current_hash.class.name}"
      Rails.logger.info "Auth hash provider: #{current_hash['provider']}"
      Rails.logger.info "Auth hash UID: #{current_hash['uid']}"
      
      # Manually find or create user to handle the auth
      @resource = resource_class.where(
        uid: current_hash['uid'],
        provider: current_hash['provider']
      ).first_or_initialize
      
      if @resource.new_record?
        Rails.logger.info "Creating new user with UID: #{current_hash['uid']}"
        @resource.email = current_hash.dig('info', 'email')
        @resource.name = current_hash.dig('info', 'name')
        @resource.password = Devise.friendly_token[0, 20]
        
        # Skip email confirmation for OAuth users
        if @resource.respond_to?(:skip_confirmation!)
          Rails.logger.info "Skipping confirmation for OAuth user"
          @resource.skip_confirmation!
        elsif @resource.respond_to?(:confirmed_at) && @resource.confirmed_at.nil?
          Rails.logger.info "Setting confirmed_at for OAuth user"
          @resource.confirmed_at = Time.current
        end
        
        @resource.save!
        Rails.logger.info "Created new user: #{@resource.id}"
      else
        Rails.logger.info "Found existing user: #{@resource.id}"
      end
      
      # Assign tokens and credentials
      @client_id = SecureRandom.urlsafe_base64(nil, false)
      @token = SecureRandom.urlsafe_base64(nil, false)
      
      @resource.tokens[@client_id] = {
        token: BCrypt::Password.create(@token),
        expiry: (Time.now + DeviseTokenAuth.token_lifespan).to_i
      }
      
      @resource.save!
      
      # Return the resource
      @resource
    else
      Rails.logger.error "Auth hash is still nil after override!"
      super
    end
  end
  
  # Handler for the default OmniAuth Keycloak strategy
  def keycloak_openid
    Rails.logger.info "In keycloak_openid callback handler"
    Rails.logger.info "Request params: #{params.inspect}"
    Rails.logger.info "OmniAuth auth data: #{request.env['omniauth.auth'].inspect}"
    Rails.logger.info "OmniAuth origin: #{request.env['omniauth.origin'].inspect}"
    Rails.logger.info "OmniAuth strategy: #{request.env['omniauth.strategy'].inspect}" if request.env['omniauth.strategy']
    
    # Super will call the main DeviseTokenAuth flow
    super
  end

  # Handler for our custom OmniAuth Keycloak strategy
  def custom_keycloak_openid
    Rails.logger.info "In custom_keycloak_openid callback handler"
    super
  end

  private

  # We're now letting DeviseTokenAuth handle the auth callback
  # This method is no longer needed
  # def handle_auth_callback
  #   # removed in favor of using the standard DeviseTokenAuth flow
  # end
end

