import { createHash, randomUUID } from 'node:crypto';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { PaymentProvider } from '../../providers/interfaces.js';
import { amountToMinorUnits, minorUnitsToAmount } from '../wallet/schemas.js';
import type { PaymentInitializationInput, PaymentInitializationResult, PaymentIntentRecord, PaymentRepositoryContract } from './types.js';

export class PaymentService {
  constructor(private readonly pool: Pool, private readonly provider: PaymentProvider, private readonly repository: PaymentRepositoryContract) {}

  verifyWebhookSignature(rawBody: string, signature: string | undefined): boolean {
    return this.provider.verifyWebhookSignature?.(rawBody, signature) ?? false;
  }

  capabilities() {
    try {
      const capabilities = this.provider.getCapabilities();
      return { providerAvailable: capabilities.available, providerName: capabilities.available ? capabilities.providerName : null, verificationAvailable: false };
    } catch {
      return { providerAvailable: false, providerName: null, verificationAvailable: false };
    }
  }

  async initialize(userId: string, input: PaymentInitializationInput, idempotencyHeader: string): Promise<PaymentInitializationResult> {
    const capabilities = this.safeCapabilities();
    if (!capabilities.available || !capabilities.providerName) throw this.providerUnavailable();

    const idempotencyKey = this.hash(`${userId}:payment:${idempotencyHeader}`);
    const { intent, createdNow } = await this.createOrReuseIntent(userId, input, idempotencyKey, capabilities.providerName);
    if (intent.providerReference) return this.toInitializationResult(intent);
    if (!createdNow || intent.status !== 'pending') {
      throw new AppError('CONFLICT', 'Payment operation is already in progress');
    }

    let providerResult: { providerReference: string; authorizationUrl?: string };
    try {
      providerResult = await this.provider.createPayment({ amount: intent.amount, currency: intent.currency, reference: intent.reference });
    } catch {
      // An exception/timeout may occur after a provider accepted the charge. Keep the intent pending to prevent a duplicate charge.
      throw this.providerUnavailable();
    }
    const providerReference = typeof providerResult?.providerReference === 'string' ? providerResult.providerReference.trim() : '';
    if (!providerReference || providerReference.length > 255) {
      // A malformed response is ambiguous; keep the intent pending for reconciliation and do not retry the provider automatically.
      throw this.providerUnavailable();
    }

    const saved = await withTransaction(this.pool, client => this.repository.saveProviderReference(client, intent.id, intent.attemptId, providerReference));
    if (!saved) throw new AppError('INTERNAL_ERROR', 'Payment initialization could not be persisted');
    return this.toInitializationResult({ ...intent, providerReference }, providerResult.authorizationUrl);
  }

  async get(userId: string, transactionId: string) {
    const intent = await this.repository.getByIdForUser(userId, transactionId);
    if (!intent) throw new AppError('NOT_FOUND', 'Payment not found');
    return { transaction: this.safeProjection(intent) };
  }

  async verify(userId: string, transactionId: string) {
    const intent = await this.repository.getByIdForUser(userId, transactionId);
    if (!intent) throw new AppError('NOT_FOUND', 'Payment not found');
    return this.verifyIntent(intent);
  }

  async handleWebhook(providerReference: string) {
    if (!this.repository.getByProviderReference) throw this.providerUnavailable();
    const intent = await this.repository.getByProviderReference(providerReference);
    if (!intent) return { handled: false };
    await this.verifyIntent(intent);
    return { handled: true, transactionId: intent.id };
  }

  private async verifyIntent(intent: PaymentIntentRecord) {
    if (!intent.providerReference) throw new AppError('CONFLICT', 'Payment has not been initialized with the provider');
    if (!this.provider.verifyPayment || !this.repository.settleProviderPayment) throw this.providerUnavailable();
    let verified: { providerReference: string; amount: string; currency: string } | null;
    try { verified = await this.provider.verifyPayment(intent.providerReference); }
    catch { throw this.providerUnavailable(); }
    if (!verified) throw new AppError('CONFLICT', 'Payment is not confirmed by the provider');
    if (verified.amount !== intent.amount || verified.currency !== intent.currency) {
      throw new AppError('CONFLICT', 'Provider payment amount or currency does not match the pending transaction');
    }
    const settled = await withTransaction(this.pool, client => this.repository.settleProviderPayment!(client, intent.id, verified!.providerReference, verified!.amount, verified!.currency));
    if (!settled) throw new AppError('CONFLICT', 'Payment could not be settled safely');
    return { transaction: { ...this.safeProjection({ ...intent, status: 'succeeded' }), status: 'succeeded' } };
  }

  private async createOrReuseIntent(userId: string, input: PaymentInitializationInput, idempotencyKey: string, providerName: string): Promise<{ intent: PaymentIntentRecord; createdNow: boolean }> {
    try {
      return await withTransaction(this.pool, async client => {
        await this.repository.lockIdempotencyKey(client, idempotencyKey);
        const existing = await this.repository.findByIdempotencyKey(client, idempotencyKey);
        if (existing) {
          if (existing.userId !== userId || !this.matchesInput(existing, input)) throw new AppError('CONFLICT', 'Idempotency key conflicts with another payment');
          if (existing.status !== 'pending') throw new AppError('CONFLICT', 'Payment operation cannot be retried');
          if (existing.providerReference && existing.providerName !== providerName) throw new AppError('CONFLICT', 'Payment provider changed for this operation');
          return { intent: existing, createdNow: false };
        }

        let amount: string;
        let currency: string;
        let walletId: string | null = null;
        let orderId: string | null = null;
        let type: 'deposit' | 'purchase';
        if (input.purpose === 'order_purchase') {
          const order = await this.repository.findOrderForBuyer(client, input.orderId, userId);
          if (!order) throw new AppError('NOT_FOUND', 'Order not found');
          if (order.status !== 'pending') throw new AppError('CONFLICT', 'Only pending orders can be paid');
          if (!/^\d+(?:\.\d{1,2})?$/.test(order.totalAmount) || amountMinorUnits(order.totalAmount) <= 0n) throw new AppError('CONFLICT', 'A zero-value order does not require external payment');
          amount = minorUnitsToAmount(amountToMinorUnits(order.totalAmount));
          currency = order.currency.toUpperCase();
          type = 'purchase';
          orderId = order.id;
        } else {
          amount = minorUnitsToAmount(amountToMinorUnits(input.amount!));
          currency = input.currency!.toUpperCase();
          const wallet = await this.repository.findDepositWallet(client, userId, currency);
          if (!wallet || wallet.status !== 'active') throw new AppError('CONFLICT', 'Wallet is not active');
          if (wallet.currency !== currency) throw new AppError('BAD_REQUEST', 'Wallet currency does not match payment currency');
          walletId = wallet.id;
          type = 'deposit';
        }

        const intent = await this.repository.createIntent(client, {
          id: randomUUID(), attemptId: randomUUID(), userId, walletId, type, amount, currency,
          reference: randomUUID(), idempotencyKey, orderId, providerName,
          attemptIdempotencyKey: this.hash(`${idempotencyKey}:attempt`)
        });
        return { intent, createdNow: true };
      });
    } catch (error) {
      if (error instanceof AppError) throw error;
      if ((error as { code?: string })?.code === '23505') throw new AppError('CONFLICT', 'A payment for this order is already pending or completed');
      if ((error as { code?: string })?.code === '23503') throw new AppError('BAD_REQUEST', 'Payment account relationship is invalid');
      throw error;
    }
  }

  private matchesInput(intent: PaymentIntentRecord, input: PaymentInitializationInput): boolean {
    if (input.purpose === 'order_purchase') return intent.type === 'purchase' && intent.orderId === input.orderId;
    return intent.type === 'deposit' && intent.amount === input.amount && intent.currency === input.currency;
  }

  private toInitializationResult(intent: PaymentIntentRecord, authorizationUrl?: string): PaymentInitializationResult {
    if (!intent.providerReference) throw new AppError('CONFLICT', 'Payment operation is already in progress');
    return {
      transaction: { id: intent.id, status: 'pending', amount: intent.amount, currency: intent.currency, reference: intent.reference, orderId: intent.orderId },
      payment: { provider: intent.providerName, providerReference: intent.providerReference, ...(authorizationUrl ? { authorizationUrl } : {}) }
    };
  }

  private safeProjection(intent: PaymentIntentRecord) {
    return { id: intent.id, type: intent.type, status: intent.status, amount: intent.amount, currency: intent.currency, reference: intent.reference, orderId: intent.orderId };
  }

  private safeCapabilities() {
    try { return this.provider.getCapabilities(); }
    catch { return { available: false, providerName: null }; }
  }

  private hash(value: string): string { return createHash('sha256').update(value).digest('hex'); }
  private providerUnavailable(): AppError { return new AppError('SERVICE_UNAVAILABLE', 'Payment provider is unavailable or not configured'); }
}

function amountMinorUnits(value: string): bigint {
  const [whole, fractional = ''] = value.split('.');
  return BigInt(whole!) * 100n + BigInt(fractional.padEnd(2, '0'));
}
