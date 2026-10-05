import { AppError } from '../../../middleware/errors.js';
import type { TranslationProvider } from '../../../providers/interfaces.js';

const maxResponseBytes = 256 * 1024;

export interface DeepLTranslationConfig {
  TRANSLATION_PROVIDER_API_KEY?: string;
  TRANSLATION_PROVIDER_BASE_URL?: string;
  TRANSLATION_PROVIDER_TIMEOUT_MS?: number;
}

export class DeepLTranslationProvider implements TranslationProvider {
  private readonly endpoint: URL;
  private readonly apiKey: string;
  private readonly timeoutMs: number;

  constructor(private readonly config: DeepLTranslationConfig) {
    if (!config.TRANSLATION_PROVIDER_API_KEY) throw new Error('DeepL API key is required');
    this.apiKey = config.TRANSLATION_PROVIDER_API_KEY;
    this.endpoint = new URL(
      config.TRANSLATION_PROVIDER_BASE_URL ||
      'https://api-free.deepl.com/v2/translate'
    );
    if (this.endpoint.protocol !== 'https:') throw new Error('DeepL endpoint must use HTTPS');
    this.timeoutMs = config.TRANSLATION_PROVIDER_TIMEOUT_MS ?? 10_000;
  }

  getCapabilities() {
    return { available: true, supportedLanguages: null };
  }

  async translate(input: { text: string; source?: string; target: string }) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const body: Record<string, string | string[]> = {
        text: [input.text],
        target_lang: normalizeDeepLLanguage(input.target)
      };
      if (input.source && input.source !== 'auto') {
        body.source_lang = normalizeDeepLLanguage(input.source);
      }

      const response = await fetch(this.endpoint, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          accept: 'application/json',
          'content-type': 'application/json',
          authorization: `DeepL-Auth-Key ${this.apiKey}`
        },
        body: JSON.stringify(body)
      });

      if (!response.ok) throw unavailable();
      const raw = await readBoundedBody(response);
      const payload = JSON.parse(raw) as {
        translations?: Array<{ text?: unknown; detected_source_language?: unknown }>;
      };
      const translation = payload.translations?.[0];
      if (!translation || typeof translation.text !== 'string' || !translation.text.trim()) throw unavailable();

      return {
        text: translation.text.trim(),
        providerReference: typeof translation.detected_source_language === 'string'
          ? translation.detected_source_language
          : undefined
      };
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw unavailable();
    } finally {
      clearTimeout(timer);
    }
  }
}

function normalizeDeepLLanguage(value: string): string {
  const normalized = value.trim().replace('_', '-').toUpperCase();
  if (normalized === 'EN') return 'EN-US';
  return normalized;
}

async function readBoundedBody(response: Response): Promise<string> {
  if (!response.body) throw unavailable();
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const chunks: string[] = [];
  let total = 0;
  try {
    while (true) {
      const chunk = await reader.read();
      if (chunk.done) break;
      total += chunk.value.byteLength;
      if (total > maxResponseBytes) {
        await reader.cancel();
        throw unavailable();
      }
      chunks.push(decoder.decode(chunk.value, { stream: true }));
    }
    chunks.push(decoder.decode());
    return chunks.join('');
  } finally {
    reader.releaseLock();
  }
}

function unavailable(): AppError {
  return new AppError('SERVICE_UNAVAILABLE', 'Translation provider is unavailable');
}
