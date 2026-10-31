import { AppError } from '../../middleware/errors.js';
import type { TranslationInput, TranslationProvider, TranslationRecord, TranslationRepositoryContract } from './types.js';
import { canonicalLanguageCode } from './types.js';

export interface TranslationLanguage {
  code: string;
  name: string;
}

export class TranslationService {
  private languageCache: { expiresAt: number; languages: TranslationLanguage[] | null } | null = null;
  private languageRequest: Promise<TranslationLanguage[] | null> | null = null;

  constructor(private readonly provider: TranslationProvider, private readonly repository: TranslationRepositoryContract) {}

  async capabilities() {
    let capabilities: ReturnType<TranslationProvider['getCapabilities']>;
    try {
      capabilities = this.provider.getCapabilities();
    } catch {
      return { providerAvailable: false, supportedLanguages: null, languages: [] as TranslationLanguage[] };
    }
    if (!capabilities.available) {
      return { providerAvailable: false, supportedLanguages: null, languages: [] as TranslationLanguage[] };
    }
    const languages = await this.readLanguageCatalog(capabilities.supportedLanguages);
    if (!languages?.length) {
      return { providerAvailable: false, supportedLanguages: null, languages: [] as TranslationLanguage[] };
    }
    return {
      providerAvailable: true,
      supportedLanguages: languages.map(language => language.code),
      languages
    };
  }

  async translate(userId: string, input: TranslationInput) {
    const sourceLanguage = input.sourceLanguage ?? 'auto';
    const request = await this.repository.createPending(userId, {
      text: input.text,
      sourceLanguage,
      targetLanguage: input.targetLanguage
    });
    let capabilities: ReturnType<TranslationProvider['getCapabilities']>;
    try { capabilities = this.provider.getCapabilities(); }
    catch { return this.failUnavailable(userId, request.id); }
    if (!capabilities.available) return this.failUnavailable(userId, request.id);

    const languages = await this.readLanguageCatalog(capabilities.supportedLanguages);
    if (!languages?.length) return this.failUnavailable(userId, request.id);
    const supported = new Set(languages.map(language => language.code));
    if (!supported.has(input.targetLanguage) || (input.sourceLanguage && !supported.has(input.sourceLanguage))) {
      await this.repository.markFailed(userId, request.id);
      throw new AppError('VALIDATION_ERROR', 'The selected language is not supported by the translation service', { requestId: request.id });
    }

    let result: { text: string; providerReference?: string };
    try {
      result = await this.provider.translate({ text: input.text, source: input.sourceLanguage, target: input.targetLanguage });
    } catch {
      return this.failUnavailable(userId, request.id);
    }
    const translatedText = typeof result?.text === 'string' ? result.text.trim() : '';
    if (!translatedText || Array.from(translatedText).length > 20_000) return this.failUnavailable(userId, request.id);
    const providerReference = typeof result.providerReference === 'string' && result.providerReference.length <= 255
      ? result.providerReference
      : null;
    if (!await this.repository.markSucceeded(userId, request.id, translatedText, providerReference)) {
      throw new AppError('INTERNAL_ERROR', 'Translation result could not be persisted');
    }
    return {
      id: request.id,
      sourceLanguage,
      targetLanguage: input.targetLanguage,
      text: input.text,
      translatedText,
      status: 'succeeded' as const,
      createdAt: request.createdAt
    };
  }

  async getRequest(userId: string, requestId: string): Promise<{ request: TranslationRecord }> {
    const request = await this.repository.getForUser(userId, requestId);
    if (!request) throw new AppError('NOT_FOUND', 'Translation request not found');
    return { request };
  }

  private async readLanguageCatalog(fallback: readonly string[] | null): Promise<TranslationLanguage[] | null> {
    if (this.languageCache && this.languageCache.expiresAt > Date.now()) return this.languageCache.languages;
    if (this.languageRequest) return this.languageRequest;
    this.languageRequest = (async () => {
      try {
        let languages: readonly { code: string; name: string }[] | null = null;
        if (this.provider.listLanguages) {
          languages = await this.provider.listLanguages();
        } else if (fallback !== null) {
          languages = fallback.map(code => ({ code, name: code }));
        }
        if (languages === null) {
          this.languageCache = { expiresAt: Date.now() + 60_000, languages: null };
          return null;
        }
        const cleaned = new Map<string, TranslationLanguage>();
        for (const language of languages) {
          if (typeof language.code !== 'string' || typeof language.name !== 'string') continue;
          let code: string;
          try { code = canonicalLanguageCode(language.code); } catch { continue; }
          const name = language.name.trim();
          if (!name || name.length > 80) continue;
          cleaned.set(code, { code, name });
        }
        const result = [...cleaned.values()].sort((a, b) => a.name.localeCompare(b.name));
        this.languageCache = {
          expiresAt: Date.now() + (result.length ? 6 * 60 * 60_000 : 60_000),
          languages: result.length ? result : null
        };
        return this.languageCache.languages;
      } catch {
        this.languageCache = { expiresAt: Date.now() + 60_000, languages: null };
        return null;
      } finally {
        this.languageRequest = null;
      }
    })();
    return this.languageRequest;
  }

  private async failUnavailable(userId: string, requestId: string): Promise<never> {
    await this.repository.markFailed(userId, requestId);
    throw new AppError('SERVICE_UNAVAILABLE', 'Translation is temporarily unavailable', { requestId });
  }
}
