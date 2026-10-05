import { AppError } from '../../../middleware/errors.js';
import type { AIProvider } from '../../../providers/interfaces.js';

export class UnavailableAIProvider implements AIProvider {
  getCapabilities() { return { available: false, providerName: null }; }

  async complete(_input: Parameters<AIProvider['complete']>[0]): Promise<{ text: string }> {
    throw new AppError('SERVICE_UNAVAILABLE', 'Eazy Assist AI provider is unavailable');
  }
}
