import { replaceChatwootName } from '../installationName';

describe('replaceChatwootName', () => {
  afterEach(() => {
    delete window.globalConfig;
  });

  it('names the installation instead of Chatwoot', () => {
    window.globalConfig = { INSTALLATION_NAME: 'starsign' };
    expect(replaceChatwootName('Welcome to Chatwoot')).toBe('Welcome to starsign');
    expect(replaceChatwootName('chatwoot and CHATWOOT')).toBe('starsign and starsign');
  });

  it('leaves domains and addresses alone', () => {
    window.globalConfig = { INSTALLATION_NAME: 'starsign' };
    expect(replaceChatwootName('see https://www.chatwoot.com/docs')).toBe('see https://www.chatwoot.com/docs');
    expect(replaceChatwootName('mail hello@chatwoot.com')).toBe('mail hello@chatwoot.com');
    expect(replaceChatwootName('chatwoot.help')).toBe('chatwoot.help');
  });

  it('changes nothing without an installation name, or for non-strings', () => {
    expect(replaceChatwootName('Chatwoot')).toBe('Chatwoot');
    window.globalConfig = { INSTALLATION_NAME: 'Chatwoot' };
    expect(replaceChatwootName('Chatwoot')).toBe('Chatwoot');
    window.globalConfig = { INSTALLATION_NAME: 'starsign' };
    const vnode = { type: 'span' };
    expect(replaceChatwootName(vnode)).toBe(vnode);
  });
});
