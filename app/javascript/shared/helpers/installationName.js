// Vital's fork: every translated string names the installation, not Chatwoot, in one place (vue-i18n's
// postTranslation) rather than edited in each locale file (planning_vital_ai_api/15 §3b). The server puts
// INSTALLATION_NAME in window.globalConfig on the dashboard, sign-in, widget and survey pages.
// "Chatwoot" as part of a domain or address (chatwoot.com, @chatwoot) is left alone.
const CHATWOOT_WORD = /(?<![./@-])\bchatwoot\b(?![.-]\w)/gi;

export const replaceChatwootName = text => {
  const name = window.globalConfig?.INSTALLATION_NAME;
  if (typeof text !== 'string' || !name || name.toLowerCase() === 'chatwoot') {
    return text;
  }
  return text.replace(CHATWOOT_WORD, name);
};

export const postTranslation = str => replaceChatwootName(str);

// Upstream's own test for a custom-branded installation (globalConfig/isACustomBrandedInstance), usable before the
// store exists. Provisioning sets our INSTALLATION_NAME, so this is true on every Vital installation.
export const isCustomBranded = () => {
  const name = window.globalConfig?.INSTALLATION_NAME;
  return Boolean(name) && name.toLowerCase() !== 'chatwoot';
};

// A link to Chatwoot's site, or '' on a custom-branded installation. Links left empty are hidden by the layout
// (a[href=""] in vueapp.html.erb), and code that opens or fetches one checks for ''.
export const chatwootLink = url => (isCustomBranded() ? '' : url);
