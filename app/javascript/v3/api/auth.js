import {
  setAuthCredentials,
  throwErrorMessage,
  clearLocalStorageOnLogout,
} from 'dashboard/store/utils/api';
import wootAPI from './apiClient';
import { getLoginRedirectURL } from '../helpers/AuthHelper';

export const login = async ({
  ssoAccountId,
  ssoConversationId,
  ...credentials
}) => {
  try {
    console.log('[AUTH] Login attempt with:', { 
      ssoAuthToken: credentials.sso_auth_token ? 'present' : 'not present',
      ssoAccountId: ssoAccountId || 'not present',
      ssoConversationId: ssoConversationId || 'not present',
      email: credentials.email ? 'present' : 'not present',
    });
    
    // Normal login flow with API call
    console.log('[AUTH] Proceeding with login API call');
    const response = await wootAPI.post('auth/sign_in', credentials);
    
    console.log('[AUTH] Login API response received:', {
      status: response.status,
      headers: response.headers ? 'present' : 'not present',
      data: response.data ? 'present' : 'not present'
    });
    
    setAuthCredentials(response);
    clearLocalStorageOnLogout();
    
    const redirectUrl = getLoginRedirectURL({
      ssoAccountId,
      ssoConversationId,
      user: response.data.data,
    });
    
    console.log('[AUTH] Redirecting to dashboard after successful login:', redirectUrl);
    window.location = redirectUrl;
  } catch (error) {
    console.error('[AUTH] Login error:', error);
    throwErrorMessage(error);
  }
};

export const register = async creds => {
  try {
    const response = await wootAPI.post('api/v1/accounts.json', {
      account_name: creds.accountName.trim(),
      user_full_name: creds.fullName.trim(),
      email: creds.email,
      password: creds.password,
      h_captcha_client_response: creds.hCaptchaClientResponse,
    });
    setAuthCredentials(response);
    return response.data;
  } catch (error) {
    throwErrorMessage(error);
  }
  return null;
};

export const verifyPasswordToken = async ({ confirmationToken }) => {
  try {
    const response = await wootAPI.post('auth/confirmation', {
      confirmation_token: confirmationToken,
    });
    setAuthCredentials(response);
  } catch (error) {
    throwErrorMessage(error);
  }
};

export const setNewPassword = async ({
  resetPasswordToken,
  password,
  confirmPassword,
}) => {
  try {
    const response = await wootAPI.put('auth/password', {
      reset_password_token: resetPasswordToken,
      password_confirmation: confirmPassword,
      password,
    });
    setAuthCredentials(response);
  } catch (error) {
    throwErrorMessage(error);
  }
};

export const resetPassword = async ({ email }) =>
  wootAPI.post('auth/password', { email });
