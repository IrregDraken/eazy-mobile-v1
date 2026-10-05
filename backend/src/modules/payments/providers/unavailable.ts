import type { PaymentProvider } from '../../../providers/interfaces.js';

export class UnavailablePaymentProvider implements PaymentProvider {
  getCapabilities() { return { available: false, providerName: null }; }
  async createPayment(): Promise<{ providerReference: string }> { throw new Error('No payment provider is configured'); }
  async verifyPayment(): Promise<null> { throw new Error('No payment provider is configured'); }
  verifyWebhookSignature(): boolean { return false; }
}
