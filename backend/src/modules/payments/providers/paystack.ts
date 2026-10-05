import crypto from 'node:crypto';
import type { AppConfig } from '../../../config/env.js';
import type { PaymentProvider } from '../../../providers/interfaces.js';

export interface VerifiedPayment {
  providerReference: string;
  amount: string;
  currency: string;
}

export class PaystackPaymentProvider implements PaymentProvider {
  private readonly secretKey: string;
  private readonly webhookSecret: string;
  private readonly enabled: boolean;

  constructor(private readonly config: AppConfig) {
    this.secretKey = config.PAYSTACK_SECRET_KEY ?? '';
    this.webhookSecret = config.PAYSTACK_WEBHOOK_SECRET || this.secretKey;
    this.enabled = config.PAYSTACK_ENABLED === true && Boolean(this.secretKey);
  }

  getCapabilities() {
    return { available: this.enabled, providerName: this.enabled ? 'paystack' : null };
  }

  async createPayment(input: { amount: string; currency: string; reference: string }) {
    this.assertEnabled();
    const response = await fetch('https://api.paystack.co/transaction/initialize', {
      method: 'POST',
      headers: { authorization: `Bearer ${this.secretKey}`, 'content-type': 'application/json' },
      body: JSON.stringify({ amount: amountToMinorUnits(input.amount), currency: input.currency, reference: input.reference, callback_url: this.config.PAYMENT_CALLBACK_URL || undefined })
    });
    const payload = await response.json() as { status?: boolean; message?: string; data?: { reference?: string; authorization_url?: string } };
    if (!response.ok || payload.status !== true || !payload.data?.reference) throw new Error(payload.message ?? 'Paystack payment initialization failed');
    return { providerReference: payload.data.reference, authorizationUrl: payload.data.authorization_url };
  }

  async verifyPayment(providerReference: string): Promise<VerifiedPayment | null> {
    this.assertEnabled();
    const response = await fetch(`https://api.paystack.co/transaction/verify/${encodeURIComponent(providerReference)}`, {
      headers: { authorization: `Bearer ${this.secretKey}` }
    });
    const payload = await response.json() as { status?: boolean; data?: { reference?: string; status?: string; amount?: number; currency?: string } };
    if (!response.ok || payload.status !== true || payload.data?.status?.toLowerCase() !== 'success') return null;
    const reference = payload.data.reference?.trim();
    const amount = payload.data.amount;
    const currency = payload.data.currency?.trim().toUpperCase();
    if (!reference || amount === undefined || !Number.isSafeInteger(amount) || amount <= 0 || !currency) return null;
    return { providerReference: reference, amount: minorUnitsToAmount(amount), currency };
  }

  verifyWebhookSignature(rawBody: string, signature: string | undefined) {
    if (!signature || !this.webhookSecret) return false;
    const expected = crypto.createHmac('sha512', this.webhookSecret).update(rawBody).digest('hex');
    const expectedBuffer = Buffer.from(expected);
    const actualBuffer = Buffer.from(signature);
    return expectedBuffer.length === actualBuffer.length && crypto.timingSafeEqual(expectedBuffer, actualBuffer);
  }

  private assertEnabled() {
    if (!this.enabled) throw new Error('Paystack payment provider is not configured');
  }
}

function amountToMinorUnits(amount: string): number {
  const [whole, fraction = ''] = amount.split('.');
  const value = Number(`${whole}.${fraction.padEnd(2, '0').slice(0, 2)}`) * 100;
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Payment amount is invalid');
  return value;
}

function minorUnitsToAmount(value: number): string {
  return (value / 100).toFixed(2);
}
