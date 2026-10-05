import type { AppConfig } from '../../../config/env.js';
import { AppError } from '../../../middleware/errors.js';
import type { AIProvider } from '../../../providers/interfaces.js';

const maxResponseBytes = 64 * 1024;
const maxOutputCharacters = 12_000;

export class OpenAICompatibleProvider implements AIProvider {
  private readonly baseUrl: URL;
  private readonly apiKey: string;
  private readonly model: string;

  constructor(private readonly config: AppConfig) {
    const base = config.AI_PROVIDER_BASE_URL;
    const key = config.AI_PROVIDER_API_KEY;
    const model = config.AI_PROVIDER_MODEL;
    if (!base || !key || !model) throw new Error('AI provider must be fully configured');
    this.baseUrl = new URL(`${base.replace(/\/+$/, '')}/`);
    this.apiKey = key;
    this.model = model;
  }

  getCapabilities() {
    return {
      available: Boolean(this.config.AI_PROVIDER_BASE_URL && this.config.AI_PROVIDER_API_KEY && this.config.AI_PROVIDER_MODEL),
      providerName: 'openai-compatible'
    };
  }

  async complete(input: Parameters<AIProvider['complete']>[0]): Promise<{ text: string; providerReference?: string }> {
    const messages = input.messages.map(message => ({ role: message.role, content: message.content }));
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.config.AI_PROVIDER_TIMEOUT_MS ?? 15_000);
    try {
      const endpoint = new URL('chat/completions', this.baseUrl);
      const response = await fetch(endpoint, {
        method: 'POST',
        redirect: 'error',
        signal: controller.signal,
        headers: { authorization: `Bearer ${this.apiKey}`, 'content-type': 'application/json' },
        body: JSON.stringify({
          model: this.model,
          messages,
          max_completion_tokens: input.maxOutputTokens,
          stream: false,
          ...(input.jsonMode ? { response_format: { type: 'json_object' } } : {})
        })
      });
      if (!response.ok) throw unavailable();
      const raw = await readBoundedBody(response);
      const payload = JSON.parse(raw) as unknown;
      if (!payload || typeof payload !== 'object') throw unavailable();
      const record = payload as { id?: unknown; choices?: unknown };
      const choices = Array.isArray(record.choices) ? record.choices : [];
      const first = choices[0];
      if (!first || typeof first !== 'object') throw unavailable();
      const message = (first as { message?: unknown }).message;
      if (!message || typeof message !== 'object') throw unavailable();
      const text = (message as { content?: unknown }).content;
      if (typeof text !== 'string' || !text.trim() || Array.from(text).length > maxOutputCharacters) throw unavailable();
      const providerReference = typeof record.id === 'string' && record.id.length > 0 && record.id.length <= 255 ? record.id : undefined;
      return { text: text.trim(), ...(providerReference ? { providerReference } : {}) };
    } catch {
      throw unavailable();
    } finally {
      clearTimeout(timeout);
    }
  }
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
  return new AppError('SERVICE_UNAVAILABLE', 'Eazy Assist provider is unavailable');
}
