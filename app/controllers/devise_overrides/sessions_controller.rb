class DeviseOverrides::SessionsController < DeviseTokenAuth::SessionsController
  include AuthHelper
  
  # Prevent session parameter from being passed
  # Unpermitted parameter: session
  wrap_parameters format: []
  before_action :process_sso_auth_token, only: [:create]

  def new
    redirect_to login_page_url(error: 'access-denied'), allow_other_host: true
  end

  def create
    # Authenticate user via the temporary sso auth token
    Rails.logger.info "SSO Debug: create method called"
    Rails.logger.info "SSO Debug: sso_auth_token present: #{params[:sso_auth_token].present?}"
    Rails.logger.info "SSO Debug: @resource present: #{@resource.present?}"
    Rails.logger.info "SSO Debug: @resource: #{@resource.inspect}"
    
    # Comprehensive header debugging for ALB investigation
    if params[:sso_auth_token].present?
      Rails.logger.info "SSO Debug: === COMPREHENSIVE HEADER ANALYSIS ==="
      Rails.logger.info "SSO Debug: request.format = #{request.format}"
      Rails.logger.info "SSO Debug: request.content_type = #{request.content_type}"
      Rails.logger.info "SSO Debug: request.xhr? = #{request.xhr?}"
      Rails.logger.info "SSO Debug: request.headers['Accept'] = #{request.headers['Accept']}"
      Rails.logger.info "SSO Debug: request.headers['Content-Type'] = #{request.headers['Content-Type']}"
      Rails.logger.info "SSO Debug: request.headers['X-Requested-With'] = #{request.headers['X-Requested-With']}"
      Rails.logger.info "SSO Debug: request.headers['User-Agent'] = #{request.headers['User-Agent']}"
      Rails.logger.info "SSO Debug: request.method = #{request.method}"
      Rails.logger.info "SSO Debug: request.url = #{request.url}"
      Rails.logger.info "SSO Debug: All request headers: #{request.headers.to_h.inspect}"
      Rails.logger.info "SSO Debug: === END HEADER ANALYSIS ==="
    end
    
    if params[:sso_auth_token].present? && @resource.present?
      Rails.logger.info "SSO Debug: Entering SSO authentication flow"
      begin
        authenticate_resource_with_sso_token
        Rails.logger.info "SSO Debug: SSO authentication completed, calling render_create_success"
        Rails.logger.info "SSO Debug: @token after authenticate_resource_with_sso_token: #{@token.inspect}"
        yield @resource if block_given?
        Rails.logger.info "SSO Debug: About to call render_create_success"
        render_create_success
        Rails.logger.info "SSO Debug: render_create_success completed successfully"
      rescue => e
        Rails.logger.error "SSO Debug: Exception in SSO flow: #{e.class}: #{e.message}"
        Rails.logger.error "SSO Debug: Backtrace: #{e.backtrace.first(5).join(', ')}"
        raise e
      end
    else
      Rails.logger.info "SSO Debug: Falling back to super (standard Devise flow)"
      super
    end
  end

  def render_create_success
    # Set the required DeviseTokenAuth headers
    send_auth_headers(@resource)
    
    # Reload the resource to ensure account associations are properly loaded
    # This fixes the race condition where active_account_user might be nil
    if @resource
      @resource.reload
      Rails.logger.info "SSO Debug: Resource reloaded, active_account_user present: #{@resource.active_account_user.present?}"
    end
    
    # The send_auth_headers method will handle setting the proper authentication headers
    # No need to assign the token struct directly to the access_token association
    
    # Add comprehensive logging to diagnose request format issues
    Rails.logger.info "SSO Debug: render_create_success called"
    Rails.logger.info "SSO Debug: request.format = #{request.format}"
    Rails.logger.info "SSO Debug: request.content_type = #{request.content_type}"
    Rails.logger.info "SSO Debug: request.headers['Accept'] = #{request.headers['Accept']}"
    Rails.logger.info "SSO Debug: request.headers['Content-Type'] = #{request.headers['Content-Type']}"
    Rails.logger.info "SSO Debug: request.xhr? = #{request.xhr?}"
    Rails.logger.info "SSO Debug: params = #{params.inspect}"
    Rails.logger.info "SSO Debug: @resource.access_token present: #{@resource.access_token.present?}"
    
    respond_to do |format|
      format.json { 
        Rails.logger.info "SSO Debug: Rendering JSON response"
        begin
          render partial: 'devise/auth', formats: [:json], locals: { resource: @resource }
          Rails.logger.info "SSO Debug: JSON response rendered successfully"
        rescue => e
          Rails.logger.error "SSO Debug: Error rendering JSON response: #{e.class}: #{e.message}"
          Rails.logger.error "SSO Debug: Backtrace: #{e.backtrace.first(3).join(', ')}"
          render json: { error: 'Authentication response error' }, status: :internal_server_error
        end
      }
      format.html { 
        Rails.logger.info "SSO Debug: Redirecting HTML request to app dashboard"
        redirect_to ENV.fetch('FRONTEND_URL', '/') + '/app/' 
      }
    end
  end

  private

  def login_page_url(error: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)

    "#{frontend_url}/app/login?error=#{error}"
  end

  def authenticate_resource_with_sso_token
    Rails.logger.info "SSO Debug: authenticate_resource_with_sso_token called"
    Rails.logger.info "SSO Debug: Creating token for user #{@resource.id}"
    
    @token = @resource.create_token
    Rails.logger.info "SSO Debug: Token created: #{@token.inspect}"
    
    @resource.save!
    Rails.logger.info "SSO Debug: Resource saved successfully"

    Rails.logger.info "SSO Debug: About to sign in user - resource valid: #{@resource.valid?}"
    Rails.logger.info "SSO Debug: Resource errors: #{@resource.errors.full_messages}" if @resource.errors.any?
    Rails.logger.info "SSO Debug: Current user before sign_in: #{current_user.inspect}"
    
    begin
      Rails.logger.info "SSO Debug: Calling sign_in with scope: :user, resource: #{@resource.class}##{@resource.id}"
      sign_in(:user, @resource, store: false, bypass: false)
      Rails.logger.info "SSO Debug: sign_in call completed"
      Rails.logger.info "SSO Debug: Current user after sign_in: #{current_user.inspect}"
      Rails.logger.info "SSO Debug: User authenticated?: #{user_signed_in?}"
    rescue => e
      Rails.logger.error "SSO Debug: Exception during sign_in: #{e.class}: #{e.message}"
      Rails.logger.error "SSO Debug: sign_in backtrace: #{e.backtrace.first(5).join(', ')}"
      raise e
    end
    
    # invalidate the token after the user is signed in
    Rails.logger.info "SSO Debug: About to invalidate SSO token"
    @resource.invalidate_sso_auth_token(params[:sso_auth_token])
    Rails.logger.info "SSO Debug: SSO token invalidated"
  end

  def process_sso_auth_token
    return if params[:email].blank?

    # URL decode the email parameter to handle double-encoded emails from OAuth redirects
    decoded_email = CGI.unescape(params[:email])
    Rails.logger.info "SSO Debug: Original email param: #{params[:email]}, Decoded: #{decoded_email}"
    
    user = User.from_email(decoded_email)
    Rails.logger.info "SSO Debug: User found: #{user.present?}, User ID: #{user&.id}"
    
    if user && params[:sso_auth_token].present?
      token_valid = user.valid_sso_auth_token?(params[:sso_auth_token])
      Rails.logger.info "SSO Debug: Token valid: #{token_valid}, Token: #{params[:sso_auth_token][0..8]}..."
      @resource = user if token_valid
    else
      Rails.logger.info "SSO Debug: Missing user or token. User: #{user.present?}, Token: #{params[:sso_auth_token].present?}"
    end
  end
end

DeviseOverrides::SessionsController.prepend_mod_with('DeviseOverrides::SessionsController')
