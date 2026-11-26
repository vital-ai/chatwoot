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
