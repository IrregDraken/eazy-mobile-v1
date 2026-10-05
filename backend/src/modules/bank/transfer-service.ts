import { createHash, randomUUID } from 'node:crypto';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { BankProvider } from '../../providers/interfaces.js';
import type { LedgerService } from '../ledger/service.js';
import { amountToMinorUnits, minorUnitsToAmount } from '../wallet/schemas.js';
import { BankTransferRepository } from './transfer-repository.js';
import type { BankTransferInput, BankTransferRecord } from './transfer-types.js';

export class BankTransferService {
  constructor(
    private readonly pool: Pool,
    private readonly provider: BankProvider,
    private readonly ledger: LedgerService,
    private readonly repository = new BankTransferRepository()
  ) {}

  verifyWebhookSignature(rawBody: string, signature: string | undefined) {
    return this.provider.verifyWebhookSignature(rawBody, signature);
  }

  capabilities() {
    const capabilities = this.provider.getCapabilities();
    return {
      providerAvailable: capabilities.available,
      providerName: capabilities.providerName,
      transfersAvailable: capabilities.available && capabilities.supportsTransfers
    };
  }

  async initiate(userId: string, input: BankTransferInput, idempotencyHeader: string) {
    const capabilities = this.capabilities();
    if (!capabilities.transfersAvailable) throw new AppError('SERVICE_UNAVAILABLE', 'Bank transfers are unavailable or not configured');

    const amount = minorUnitsToAmount(amountToMinorUnits(input.amount));
    const currency = input.currency.toUpperCase();
    const accountNumber = input.accountNumber.trim();
    const bankCode = input.bankCode.trim();
    const account = await this.resolveAndValidateAccount(accountNumber, bankCode, input.accountName);

    const idempotencyKey = this.hash(`${userId}:bank-transfer:${idempotencyHeader}`);
    let record: BankTransferRecord;
    let createdNow = false;

    try {
      const result = await withTransaction(this.pool, async client => {
        await this.repository.lockIdempotencyKey(client, idempotencyKey);
        const existing = await this.repository.findByIdempotencyKey(client, idempotencyKey);

        if (existing) {
          const fingerprint = this.accountFingerprint(accountNumber, bankCode);
          if (
            existing.userId !== userId ||
            existing.amount !== amount ||
            existing.currency !== currency ||
            existing.bankCode !== bankCode ||
            existing.accountFingerprint !== fingerprint
          ) {
            throw new AppError('CONFLICT', 'Idempotency key conflicts with another bank transfer');
          }
          return { record: existing, createdNow: false };
        }

        const wallet = await this.lockWallet(client, userId, currency);
        if (!wallet || wallet.status !== 'active') throw new AppError('CONFLICT', 'Wallet is not active');

        const balance = await this.ledger.balance(client, wallet.id);
        if (this.toMinor(balance) < amountToMinorUnits(amount)) throw new AppError('CONFLICT', 'Insufficient wallet funds');

        const pending = await this.repository.createPending(client, {
          userId,
          walletId: wallet.id,
          amount,
          currency,
          reference: randomUUID(),
          idempotencyKey,
          accountName: account.accountName,
          accountFingerprint: this.accountFingerprint(accountNumber, bankCode),
          bankCode,
          bankName: account.bankName || input.bankName
        });

        await this.ledger.recordWithdrawal(client, {
          transactionId: pending.id,
          walletId: wallet.id,
          amount,
          currency
        });

        return { record: pending, createdNow: true };
      });

      record = result.record;
      createdNow = result.createdNow;
    } catch (error) {
      if (error instanceof AppError) throw error;
      if ((error as { code?: string })?.code === '23505') throw new AppError('CONFLICT', 'A duplicate bank transfer was rejected');
      if ((error as { code?: string })?.code === '23503') throw new AppError('BAD_REQUEST', 'Financial account relationship is invalid');
      throw error;
    }

    if (!createdNow) {
      if (record.status === 'succeeded' || record.status === 'pending') return { transaction: this.safeProjection(record) };
      throw new AppError('CONFLICT', 'This bank transfer did not complete');
    }

    let recipient: { recipientCode: string };
    try {
      recipient = await this.provider.createRecipient({
        name: record.accountName,
        accountNumber,
        bankCode: record.bankCode,
        currency: record.currency
      });
    } catch {
      await this.applyProviderStatus(record.id, 'failed');
      throw new AppError('SERVICE_UNAVAILABLE', 'Bank transfer recipient setup failed; the reserved funds were returned');
    }

    await withTransaction(this.pool, client => this.repository.saveRecipient(client, record.id, recipient.recipientCode));

    let providerResult: { providerReference: string; status: 'pending' | 'success' | 'failed' };
    try {
      providerResult = await this.provider.initiateTransfer({
        recipientCode: recipient.recipientCode,
        amount: record.amount,
        currency: record.currency,
        reference: record.reference,
        reason: input.reason?.trim() || undefined
      });
    } catch {
      throw new AppError('SERVICE_UNAVAILABLE', 'Bank transfer status is pending and will be reconciled before the funds are released');
    }

    await withTransaction(this.pool, client => this.repository.saveProviderReference(client, record.id, providerResult.providerReference));

    if (providerResult.status === 'failed') {
      await this.applyProviderStatus(record.id, 'failed', providerResult.providerReference);
      throw new AppError('CONFLICT', 'Bank transfer was rejected by the provider; the funds were returned');
    }

    if (providerResult.status === 'success') {
      await this.applyProviderStatus(record.id, 'succeeded', providerResult.providerReference);
      const latest = await this.readForUser(userId, record.id);
      return { transaction: latest ? this.safeProjection(latest) : this.safeProjection({ ...record, status: 'succeeded', providerReference: providerResult.providerReference }) };
    }

    return {
      transaction: this.safeProjection({
        ...record,
        status: 'pending',
        providerReference: providerResult.providerReference,
        recipientCode: recipient.recipientCode
      })
    };
  }

  async verify(userId: string, transactionId: string) {
    const record = await this.readForUser(userId, transactionId);
    if (!record) throw new AppError('NOT_FOUND', 'Bank transfer not found');
    if (record.status !== 'pending') return { transaction: this.safeProjection(record) };
    let verified: Awaited<ReturnType<BankProvider['verifyTransfer']>>;
    try {
      verified = await this.provider.verifyTransfer(record.providerReference ?? record.reference);
    } catch {
      throw new AppError('SERVICE_UNAVAILABLE', 'Bank transfer verification is unavailable');
    }

    if (!verified) throw new AppError('CONFLICT', 'Bank transfer status is not confirmed');
    if (verified.amount !== record.amount || verified.currency !== record.currency) {
      throw new AppError('CONFLICT', 'Provider transfer amount or currency does not match');
    }

    const status = verified.status === 'success' ? 'succeeded' : verified.status === 'reversed' ? 'reversed' : verified.status === 'failed' ? 'failed' : 'pending';
    if (status !== 'pending') await this.applyProviderStatus(record.id, status, verified.providerReference);

    const refreshed = await this.readForUser(userId, record.id);
    return { transaction: refreshed ? this.safeProjection(refreshed) : this.safeProjection(record) };
  }

  async handleWebhook(event: string, providerReference: string, amount: string, currency: string) {
    if (!['transfer.success', 'transfer.failed', 'transfer.reversed'].includes(event)) return { handled: false };

    const record = await this.readByProviderReference(providerReference);
    if (!record) return { handled: false };

    if (record.amount !== minorUnitsToAmount(amountToMinorUnits(amount)) || record.currency !== currency.toUpperCase()) {
      throw new AppError('CONFLICT', 'Bank webhook amount or currency does not match');
    }

    const status = event === 'transfer.success' ? 'succeeded' : event === 'transfer.reversed' ? 'reversed' : 'failed';
    await this.applyProviderStatus(record.id, status, providerReference);
    return { handled: true, transactionId: record.id };
  }

  private async applyProviderStatus(transactionId: string, status: 'succeeded' | 'failed' | 'reversed', providerReference?: string) {
    await withTransaction(this.pool, async client => {
      const current = await this.repository.getTransactionForSettlement(client, transactionId);
      if (!current || current.status !== 'pending') return;

      await this.repository.settle(client, transactionId, status, providerReference);

      if (status !== 'succeeded') {
        await this.ledger.recordWithdrawalReversal(client, {
          transactionId,
          walletId: current.walletId,
          amount: current.amount,
          currency: current.currency
        });
      }
    });
  }

  private async resolveAndValidateAccount(accountNumber: string, bankCode: string, suppliedName: string) {
    let account: Awaited<ReturnType<BankProvider['resolveAccount']>>;
    try {
      account = await this.provider.resolveAccount({ accountNumber, bankCode });
    } catch {
      throw new AppError('SERVICE_UNAVAILABLE', 'Bank account verification is unavailable');
    }
    if (!account) throw new AppError('NOT_FOUND', 'Bank account could not be resolved');
    if (account.accountNumber !== accountNumber) throw new AppError('CONFLICT', 'Resolved bank account does not match the submitted account number');
    if (suppliedName.trim() && this.normalizeName(suppliedName) !== this.normalizeName(account.accountName)) {
      throw new AppError('CONFLICT', 'Bank account name changed; verify the account again');
    }
    return account;
  }

  private async lockWallet(client: import('../../database/client.js').DbClient, userId: string, currency: string) {
    const result = await client.query<{ id: string; status: string; currency: string }>(
      'SELECT id, status, trim(currency) AS currency FROM wallets WHERE user_id = $1 AND trim(currency) = $2 FOR UPDATE',
      [userId, currency]
    );
    return result.rows[0] ?? null;
  }

  private async readForUser(userId: string, transactionId: string) {
    const client = await this.pool.connect();
    try { return await this.repository.findForUser(client, userId, transactionId); }
    finally { client.release(); }
  }

  private async readByProviderReference(providerReference: string) {
    const client = await this.pool.connect();
    try { return await this.repository.findByProviderReference(client, providerReference); }
    finally { client.release(); }
  }

  private safeProjection(record: BankTransferRecord) {
    return {
      id: record.id,
      type: record.type,
      status: record.status,
      amount: record.amount,
      currency: record.currency,
      reference: record.reference,
      providerReference: record.providerReference,
      accountName: record.accountName,
      bankCode: record.bankCode,
      bankName: record.bankName,
      createdAt: record.createdAt
    };
  }

  private accountFingerprint(accountNumber: string, bankCode: string) {
    return createHash('sha256').update(`${bankCode}:${accountNumber}`).digest('hex');
  }

  private normalizeName(value: string) { return value.trim().toLowerCase().replace(/[^a-z0-9]+/g, ' '); }

  private toMinor(value: string) {
    const [whole, fraction = ''] = value.split('.');
    return BigInt(whole!) * 100n + BigInt(fraction.padEnd(2, '0'));
  }

  private hash(value: string) { return createHash('sha256').update(value).digest('hex'); }
}