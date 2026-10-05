import { AppError } from '../../middleware/errors.js';
import type { TranslationInput, TranslationProvider, TranslationRecord, TranslationRepositoryContract } from './types.js';
import { canonicalLanguageCode } from './types.js';

export class TranslationService {
  constructor(private readonly provider: TranslationProvider, private readonly repository: TranslationRepositoryContract) {}

  capabilities() {
    try {
      const capabilities = this.provider.getCapabilities();
      return { providerAvailable: capabilities.available, supportedLanguages: this.cleanLanguageList(capabilities.supportedLanguages) };
    } catch {
      return { providerAvailable: false, supportedLanguages: null };
    }
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
    const supported = this.cleanLanguageList(capabilities.supportedLanguages);
    if (!capabilities.available) return this.failUnavailable(userId, request.id);
    if (supported && (!supported.includes(input.targetLanguage) || (input.sourceLanguage && !supported.includes(input.sourceLanguage)))) {
      await this.repository.markFailed(userId, request.id);
      throw new AppError('VALIDATION_ERROR', 'The requested language is not supported by the configured translation provider', { requestId: request.id });
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

  private async failUnavailable(userId: string, requestId: string): Promise<never> {
    await this.repository.markFailed(userId, requestId);
    throw new AppError('SERVICE_UNAVAILABLE', 'Translation provider is unavailable', { requestId });
  }

  private cleanLanguageList(languages: readonly string[] | null): string[] | null {
    if (languages === null) return null;
    return [...new Set(languages.filter(code => {
      try { return Intl.getCanonicalLocales(code).length === 1; } catch { return false; }
    }).map(canonicalLanguageCode))];
  }
}
