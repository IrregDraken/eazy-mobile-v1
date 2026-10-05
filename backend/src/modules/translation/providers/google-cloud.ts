import { AppError } from '../../../middleware/errors.js';
import type { TranslationProvider } from '../../../providers/interfaces.js';

const maxResponseBytes = 256 * 1024;

export interface GoogleTranslationConfig {
  TRANSLATION_PROVIDER_API_KEY?: string;
  TRANSLATION_PROVIDER_BASE_URL?: string;
  TRANSLATION_PROVIDER_TIMEOUT_MS?: number;
}

export class GoogleCloudTranslationProvider implements TranslationProvider {
  private readonly baseUrl: URL;
  private readonly apiKey: string;
  private readonly timeoutMs: number;

  constructor(private readonly config: GoogleTranslationConfig) {
    if (!config.TRANSLATION_PROVIDER_API_KEY) throw new Error('Translation provider API key is required');
    this.apiKey = config.TRANSLATION_PROVIDER_API_KEY;
    this.baseUrl = new URL(config.TRANSLATION_PROVIDER_BASE_URL || 'https://translation.googleapis.com/language/translate/v2');
    if (this.baseUrl.protocol !== 'https:') throw new Error('Translation provider endpoint must use HTTPS');
    this.timeoutMs = config.TRANSLATION_PROVIDER_TIMEOUT_MS ?? 10_000;
  }

  getCapabilities() {
    return { available: true, supportedLanguages: null };
  }

  async translate(input: { text: string; source?: string; target: string }) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const url = new URL(this.baseUrl);
      url.searchParams.set('key', this.apiKey);
      const body = new URLSearchParams({ q: input.text, target: input.target, format: 'text' });
      if (input.source) body.set('source', input.source);
      const response = await fetch(url, { method: 'POST', signal: controller.signal, headers: { 'content-type': 'application/x-www-form-urlencoded' }, body });
      if (!response.ok) throw unavailable();
      const raw = await readBoundedBody(response);
      const payload = JSON.parse(raw) as { data?: { translations?: Array<{ translatedText?: unknown; detectedSourceLanguage?: unknown }> } };
      const translation = payload.data?.translations?.[0];
      if (!translation || typeof translation.translatedText !== 'string' || !translation.translatedText.trim()) throw unavailable();
      return { text: translation.translatedText.trim() };
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw unavailable();
    } finally { clearTimeout(timer); }
  }
}

async function readBoundedBody(response: Response): Promise<string> {
  if (!response.body) throw unavailable();
  const reader = response.body.getReader(); const decoder = new TextDecoder(); const chunks: string[] = []; let total = 0;
  try { while (true) { const chunk = await reader.read(); if (chunk.done) break; total += chunk.value.byteLength; if (total > maxResponseBytes) { await reader.cancel(); throw unavailable(); } chunks.push(decoder.decode(chunk.value, { stream: true })); } chunks.push(decoder.decode()); return chunks.join(''); }
  finally { reader.releaseLock(); }
}
function unavailable(): AppError { return new AppError('SERVICE_UNAVAILABLE', 'Translation provider is unavailable'); }
