class DeviseOverrides::OmniauthCallbacksController < DeviseTokenAuth::OmniauthCallbacksController
  include EmailHelper
  
  # Add a specific method for keycloak callbacks
  def keycloak
    Rails.logger.info("Keycloak callback received with params: #{request.params.inspect}")
    Rails.logger.info("Request env contents: #{request.env.keys.sort.inspect}")
    Rails.logger.info("OmniAuth strategy: #{request.env['omniauth.strategy'].inspect if request.env['omniauth.strategy']}")
    Rails.logger.info("Request env omniauth auth: #{request.env['omniauth.auth'].inspect}")
    Rails.logger.info("Request env omniauth error: #{request.env['omniauth.error'].inspect if request.env['omniauth.error']}")
    
    # If OmniAuth didn't process auth_hash correctly, we might need to handle it ourselves
    if request.env['omniauth.auth'].nil? && request.params['code'].present?
      Rails.logger.info("Attempting to handle Keycloak auth directly")
      
      # Check if we have an omniauth error
      if request.env['omniauth.error']
        Rails.logger.error("OmniAuth error: #{request.env['omniauth.error'].message}")
        Rails.logger.error("OmniAuth error type: #{request.env['omniauth.error'].class}")
      end
      
      # For now, let's try to redirect to the login page with an error message
      # In the future, we could implement direct token exchange with Keycloak
      return redirect_to login_page_url(error: 'keycloak-auth-error')
    end
    
    handle_omniauth_callback
  end
  
  # Keep the original method for other providers (like Google)
  def omniauth_success
    handle_omniauth_callback
  end
  
  def handle_omniauth_callback
    get_resource_from_auth_hash
    @resource.present? ? sign_in_user : sign_up_user
  end

  private

  def sign_in_user
    @resource.skip_confirmation! if confirmable_enabled?

    # once the resource is found and verified
    # we can just send them to the login page again with the SSO params
    # that will log them in
    encoded_email = ERB::Util.url_encode(@resource.email)
    redirect_to login_page_url(email: encoded_email, sso_auth_token: @resource.generate_sso_auth_token), allow_other_host: true
  end

  def sign_up_user
    return redirect_to login_page_url(error: 'no-account-found'), allow_other_host: true unless account_signup_allowed?
    return redirect_to login_page_url(error: 'business-account-only'), allow_other_host: true unless validate_signup_email_is_business_domain?

    create_account_for_user
    token = @resource.send(:set_reset_password_token)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    redirect_to "#{frontend_url}/app/auth/password/edit?config=default&reset_password_token=#{token}", allow_other_host: true
  end

  def login_page_url(error: nil, email: nil, sso_auth_token: nil)
    frontend_url = ENV.fetch('FRONTEND_URL', nil)
    params = { email: email, sso_auth_token: sso_auth_token }.compact
    params[:error] = error if error.present?

    "#{frontend_url}/app/login?#{params.to_query}"
  end

  def account_signup_allowed?
    # set it to true by default, this is the behaviour across the app
    GlobalConfigService.load('ENABLE_ACCOUNT_SIGNUP', 'false') != 'false'
  end

  def resource_class(_mapping = nil)
    User
  end

  # Make sure we have access to auth_hash
  def auth_hash
    request.env['omniauth.auth']
  end

  def get_resource_from_auth_hash # rubocop:disable Naming/AccessorMethodName
    # find the user with their email instead of UID and token
    Rails.logger.info("Auth hash in get_resource_from_auth_hash: #{auth_hash.inspect}")
    
    # Safely access the email with checks to prevent nil errors
    if auth_hash && auth_hash['info'] && auth_hash['info']['email'].present?
      @resource = resource_class.where(
        email: auth_hash['info']['email']
      ).first
    else
      Rails.logger.error("Invalid auth_hash structure: #{auth_hash.inspect}")
      nil
    end
  end

  def validate_signup_email_is_business_domain?
    # return true if the user is a business account, false if it is a blocked domain account
    if auth_hash && auth_hash['info'] && auth_hash['info']['email'].present?
      Account::SignUpEmailValidationService.new(auth_hash['info']['email']).perform
    else
      Rails.logger.error("Missing email in auth_hash for validation: #{auth_hash.inspect}")
      false
    end
  rescue CustomExceptions::Account::InvalidEmail
    false
  end

  def create_account_for_user
    if auth_hash && auth_hash['info'] && auth_hash['info']['email'].present?
      email = auth_hash['info']['email']
      name = auth_hash['info']['name'] || email.split('@').first
      email_verified = auth_hash['info']['email_verified'] || false
      
      @resource, @account = AccountBuilder.new(
        account_name: extract_domain_without_tld(email),
        user_full_name: name,
        email: email,
        locale: I18n.locale,
        confirmed: email_verified
      ).perform
      
      if auth_hash['info']['image'].present?
        Avatar::AvatarFromUrlJob.perform_later(@resource, auth_hash['info']['image'])
      end
    else
      Rails.logger.error("Cannot create account: Missing info in auth_hash: #{auth_hash.inspect}")
      nil
    end
  end

  def default_devise_mapping
    'user'
  end
end
