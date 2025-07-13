<script>
import SimpleDivider from '../Divider/SimpleDivider.vue';

export default {
  components: {
    SimpleDivider,
  },
  props: {
    showSeparator: {
      type: Boolean,
      default: true,
    },
  },
  methods: {
    getKeycloakAuthUrl() {
      // Creating the URL manually similar to how the Google OAuth URL is created
      // This is because devise-token-auth with omniauth has a standing issue on redirecting the post request
      // https://github.com/lynndylanhurley/devise_token_auth/issues/1466
      const baseUrl = window.chatwootConfig.keycloakSiteUrl;
      if (!baseUrl) {
        console.error('Keycloak site URL not configured');
        return '#';
      }

      const realm = window.chatwootConfig.keycloakRealm || 'master';
      const clientId = window.chatwootConfig.keycloakClientId;
      const redirectUri = window.chatwootConfig.keycloakCallbackUrl;
      const responseType = 'code';
      const scope = 'openid email profile';

      // Build the query string
      const queryString = new URLSearchParams({
        client_id: clientId,
        redirect_uri: redirectUri,
        response_type: responseType,
        scope: scope,
      }).toString();

      // Construct the full URL for Keycloak authorization endpoint
      return `${baseUrl}/realms/${realm}/protocol/openid-connect/auth?${queryString}`;
    }
  },
};
</script>

<!-- eslint-disable vue/no-unused-refs -->
<!-- Added ref for writing specs -->
<template>
  <div class="flex flex-col">
    <a
      :href="getKeycloakAuthUrl()"
      class="inline-flex justify-center w-full px-4 py-3 bg-n-background dark:bg-n-solid-3 rounded-md shadow-sm ring-1 ring-inset ring-n-container dark:ring-n-container focus:outline-offset-0 hover:bg-n-alpha-2 dark:hover:bg-n-alpha-2"
    >
      <!-- Using a K icon since there's no built-in Keycloak icon -->
      <span class="flex items-center justify-center h-6 w-6 text-center font-bold text-n-slate-12 bg-n-slate-2 rounded">K</span>
      <span class="ml-2 text-base font-medium text-n-slate-12">
        {{ $t('LOGIN.OAUTH.KEYCLOAK_LOGIN') }}
      </span>
    </a>
    <SimpleDivider
      v-if="showSeparator"
      ref="divider"
      :label="$t('COMMON.OR')"
      class="uppercase"
    />
  </div>
</template>
