import type { TranslationProvider, TranslationProviderResult } from '../types.js';

export class UnavailableTranslationProvider implements TranslationProvider {
  getCapabilities() {
    return { available: false, supportedLanguages: null } as const;
  }

  async translate(_input: { text: string; source?: string; target: string }): Promise<TranslationProviderResult> {
    throw new Error('Translation provider is not configured');
  }
}
