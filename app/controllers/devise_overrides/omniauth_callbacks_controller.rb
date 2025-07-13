class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  
  # Override auth_hash getter to ensure we always have valid data
  def auth_hash
    # Get the auth_hash from super or fall back to omniauth.auth
    @auth_hash ||= begin
      # Try to get from parent class
      Rails.logger.info "=== DEBUG: Getting auth_hash ==="
      hash = super
      Rails.logger.info "Auth hash from super: #{hash ? 'Present' : 'Nil'}"
      
      # If nil, create from request env
      if hash.nil?
        Rails.logger.info "=== DEBUG: Creating auth_hash from omniauth.auth ==="
        raw_auth = request.env['omniauth.auth']
        
        if raw_auth
          # Log key auth data for debugging
          Rails.logger.info "Auth data found in request.env['omniauth.auth']"
          Rails.logger.info "Auth UID: #{raw_auth['uid'].inspect}" if raw_auth['uid']
          Rails.logger.info "Auth provider: #{raw_auth['provider'].inspect}" if raw_auth['provider']
          Rails.logger.info "Auth info: #{raw_auth['info'].inspect}" if raw_auth['info']
          Rails.logger.info "Auth email: #{raw_auth.dig('info', 'email').inspect}" if raw_auth['info']
          
          # Check for presence of required fields
          if raw_auth['uid'].blank?
            Rails.logger.error "WARNING: Auth hash is missing UID - this will cause validation errors"
            # Try to set it from other fields if possible
            raw_auth['uid'] = raw_auth.dig('info', 'sub') || 
                              raw_auth.dig('extra', 'raw_info', 'sub') || 
                              raw_auth.dig('extra', 'raw_info', 'preferred_username') || 
                              SecureRandom.uuid
            Rails.logger.info "Using fallback UID: #{raw_auth['uid']}"
          end
          
          if raw_auth.dig('info', 'email').blank?
            Rails.logger.error "WARNING: Auth hash is missing email - user creation may fail"
          end
          
          # Return the raw_auth as is - don't modify the structure as DeviseTokenAuth expects
          # the OmniAuth::AuthHash format, not a regular hash
          hash = raw_auth
        else
          # Create minimal hash with data from params if we can't find auth data
          Rails.logger.warn "No auth data in omniauth.auth, creating minimal hash from params"
          uuid = SecureRandom.uuid
          hash = OmniAuth::AuthHash.new(
            'uid' => params['code'] || uuid,
            'provider' => params['provider'] || 'keycloak_openid',
            'info' => { 
              'email' => "user-#{uuid}@example.com", # Generate email to prevent validation errors
              'name' => "User #{uuid.split('-').first}"
            }
          )
          Rails.logger.info "Created minimal hash: uid=#{hash['uid']}, email=#{hash.dig('info', 'email')}"
        end
      end
      
      # Final verification before returning
      if hash && hash['uid'].blank?
        Rails.logger.error "CRITICAL: Auth hash still has blank UID after processing"
        hash['uid'] = SecureRandom.uuid
        Rails.logger.info "Emergency UID assigned: #{hash['uid']}"
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
  
  # Handler for the Keycloak OpenID OmniAuth strategy
  def keycloak_openid
    Rails.logger.info "=== KEYCLOAK AUTH CALLBACK STARTED ==="
    Rails.logger.info "Request params: #{params.inspect}"
    
    begin
      # Debug auth hash
      if request.env['omniauth.auth']
        auth_data = request.env['omniauth.auth']
        Rails.logger.info "OmniAuth auth data: Provider=#{auth_data['provider']}, UID=#{auth_data['uid']}"
        Rails.logger.info "Auth info: #{auth_data['info'].inspect}" if auth_data['info']
        Rails.logger.info "Auth extra: #{auth_data['extra'].inspect}" if auth_data['extra']
      else
        Rails.logger.warn "No omniauth.auth data in request environment"
        redirect_to '/app/login?auth_failed=true&reason=no_auth_data'
        return
      end
      
      # Find or create user from auth hash
      @resource = get_resource_from_auth_hash
      
      if @resource && @resource.persisted?
        Rails.logger.info "User found/created with ID=#{@resource.id}"
        
        # Check if this is the first user in the system
        if first_user?
          Rails.logger.info "This appears to be the first user in the system"
          handle_first_user_bootstrap(@resource)
        end
        
        # Sign in the user - this is important for session establishment
        Rails.logger.info "Signing in user ID=#{@resource.id}"
        sign_in(:user, @resource, event: :authentication)
        
        # Generate auth tokens for API access - use methods consistent with email login
        @client_id = SecureRandom.urlsafe_base64(nil, false)
        @token = @resource.create_token
        @resource.tokens[@client_id] = {
          token: BCrypt::Password.create(@token),
          expiry: (Time.now + DeviseTokenAuth.token_lifespan).to_i
        }
        
        # Save user with new tokens
        Rails.logger.info "Saving user with new auth tokens"
        @resource.save!
        
        # Build auth headers exactly as DeviseTokenAuth does
        auth_headers = @resource.build_auth_headers(@token, @client_id)
        Rails.logger.info "Generated auth headers: #{auth_headers.keys}"
        
        # Set headers for API access - these are what the frontend looks for
        response.headers.merge!(auth_headers)
        
        # Add a parameter to the redirect URL to help the frontend prevent infinite loops
        @auth_origin_url = "#{after_sign_in_path_for(@resource)}?sso_in_progress=true"
        
        # Return a JSON response with user data
        # The frontend will read the authentication headers from the response and set cookies
        Rails.logger.info "Authentication successful, returning JSON response with auth headers"
        Rails.logger.info "Auth headers: access-token=#{auth_headers['access-token'][0..5]}..., client=#{auth_headers['client']}, uid=#{auth_headers['uid']}"
        
        render json: {
          data: @resource.as_json(
            only: [:id, :email, :uid, :name, :nickname, :image, :provider],
            methods: [:provider])
        }, status: :ok
        return
      else
        Rails.logger.error "Failed to save user: #{@resource&.errors&.full_messages&.join(', ')}"
        render json: { 
          error: "Authentication failed",
          reason: "Failed to create or authenticate user"
        }, status: :unprocessable_entity
        return
      end
    rescue => e
      Rails.logger.error "EXCEPTION in keycloak_openid: #{e.class.name} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      render json: { 
        error: "Authentication failed",
        reason: e.message 
      }, status: :unprocessable_entity
    ensure
      Rails.logger.info "=== KEYCLOAK AUTH PROCESS COMPLETED ===" 
    end
  end
  
  private

  # Check if this is the first user in the system
  def first_user?
    user_count = User.count
    account_count = Account.count
    
    Rails.logger.info "Checking first user status: user_count=#{user_count}, account_count=#{account_count}"
    
    # If this is the only user and there are no accounts, this is the first user
    user_count == 1 && account_count == 0
  end

  # Bootstrap the first user as an administrator
  def handle_first_user_bootstrap(user)
    Rails.logger.info "Bootstrapping first user #{user.email} as administrator"
    
    # Create default account for the first user
    account = Account.create!(
      name: 'Default',
      locale: I18n.default_locale
    )
    
    # Associate user with account as administrator
    AccountUser.create!(
      account: account,
      user: user,
      role: :administrator
    )
    
    Rails.logger.info "Created default account and assigned admin role to first user #{user.email}"
  end

  # Complete the authentication handoff to frontend
  def complete_authentication
    if @resource
      # Set auth headers for API access
      auth_headers = @resource.create_new_auth_token(@client_id)
      response.headers.merge!(auth_headers)
      
      # For cookie auth in browser
      cookies[@resource.class.headers_names[:'access-token']] = {
        value: auth_headers['access-token'],
        httponly: true
      }
      
      cookies[@resource.class.headers_names[:'client']] = {
        value: auth_headers['client'],
        httponly: true
      }
      
      # DO NOT call sign_in_and_redirect here as it's already handled by super
      # This was causing the infinite redirect loop
      # Instead, just sign in the user without redirect
      sign_in @resource, event: :authentication
      
      Rails.logger.info "Authentication complete for user #{@resource.email}"
    else
      Rails.logger.error "Cannot complete authentication - no resource"
    end
  end
end
