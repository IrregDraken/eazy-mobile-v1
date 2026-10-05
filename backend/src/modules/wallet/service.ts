import { createHash, randomUUID } from 'node:crypto';
import type { Pool } from 'pg';
import { withTransaction, type DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import type { LedgerService } from '../ledger/service.js';
import type { TransferInput, WalletRepositoryContract, WalletTransactionProjection } from './types.js';
import { amountToMinorUnits, minorUnitsToAmount } from './schemas.js';

export class WalletService {
  constructor(private readonly pool: Pool, private readonly repository: WalletRepositoryContract, private readonly ledger: LedgerService) {}

  async getWallets(userId: string) {
    const wallets = await this.repository.listWallets(userId);
    return { wallet: wallets[0] ?? null };
  }

  async createWallet(userId: string, currency: string) {
    const wallet = await withTransaction(this.pool, client => this.repository.createOrGetWallet(client, userId, currency));
    if (wallet.currency !== currency) throw new AppError('CONFLICT', 'A wallet already exists in another currency');
    return { wallet: { id: wallet.id, currency: wallet.currency, status: wallet.status } };
  }

  async listTransactions(userId: string, pagination: Pagination) {
    const result = await this.repository.listTransactions(userId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  async getTransaction(userId: string, transactionId: string) {
    const transaction = await this.repository.getTransaction(userId, transactionId);
    if (!transaction) throw new AppError('NOT_FOUND', 'Transaction not found');
    return { transaction };
  }

  async transfer(userId: string, input: TransferInput, key: string) {
    const keyHash = this.scopedKey(userId, 'wallet-transfer', key);
    const amount = minorUnitsToAmount(amountToMinorUnits(input.amount));
    return this.transferToUser(userId, input.recipientUsername, amount, input.currency, keyHash, 'transfer');
  }

  async payQr(userId: string, resolveRecipient: (client: DbClient, allowInactive: boolean) => Promise<{ userId: string; username: string; displayName: string }>, amount: string, currency: string, key: string) {
    amount = minorUnitsToAmount(amountToMinorUnits(amount));
    const keyHash = this.scopedKey(userId, 'qr-payment', key);
    return this.transferToUser(userId, null, amount, currency, keyHash, 'qr_payment', resolveRecipient);
  }

  private async transferToUser(
    userId: string,
    recipientUsername: string | null,
    amount: string,
    currency: string,
    idempotencyKey: string,
    type: 'transfer' | 'qr_payment',
    qrRecipientResolver?: (client: DbClient, allowInactive: boolean) => Promise<{ userId: string; username: string; displayName: string }>
  ) {
    amountToMinorUnits(amount);
    try {
      return await withTransaction(this.pool, async client => {
        await this.repository.lockIdempotencyKey(client, idempotencyKey);
        const existing = await this.repository.findByIdempotencyKey(client, idempotencyKey);
        const recipient = recipientUsername
          ? await this.repository.resolveRecipientByUsername(client, recipientUsername)
          : qrRecipientResolver ? await qrRecipientResolver(client, existing !== null) : null;
        const resolvedRecipientId = recipient?.userId;
        if (!resolvedRecipientId) throw new AppError('NOT_FOUND', 'Recipient not found');
        if (resolvedRecipientId === userId) throw new AppError('BAD_REQUEST', 'A wallet cannot transfer to itself');

        if (existing) {
          if (existing.userId !== userId || existing.type !== type || existing.amount !== amount || existing.currency !== currency || !existing.counterpartyWalletId) {
            throw new AppError('CONFLICT', 'Idempotency key conflicts with another financial operation');
          }
          const existingRecipientId = await this.repository.findTransferRecipient(client, existing.id);
          if (existingRecipientId !== resolvedRecipientId) throw new AppError('CONFLICT', 'Idempotency key conflicts with another financial operation');
          if (existing.status !== 'succeeded') throw new AppError('CONFLICT', 'This transfer did not complete');
          return { transaction: this.transactionProjection(existing), recipient: recipientUsername ? { username: recipient.username, displayName: recipient.displayName } : { username: recipient.username, displayName: recipient.displayName } };
        }

        const participantIds = [userId, resolvedRecipientId].sort();
        const wallets = new Map<string, { id: string; userId: string; currency: string; status: string }>();
        for (const participantId of participantIds) {
          const wallet = await this.repository.findWalletForUser(client, participantId);
          if (wallet) wallets.set(participantId, wallet);
        }
        const locked = await this.repository.lockWallets(client, participantIds);
        for (const wallet of locked) wallets.set(wallet.userId, wallet);
        const senderWallet = wallets.get(userId);
        const recipientWallet = wallets.get(resolvedRecipientId);
        if (!senderWallet || !recipientWallet) throw new AppError('NOT_FOUND', 'Wallet not found');
        if (senderWallet.status !== 'active' || recipientWallet.status !== 'active') throw new AppError('CONFLICT', 'Wallet is not active');
        if (senderWallet.currency !== currency || recipientWallet.currency !== currency) throw new AppError('BAD_REQUEST', 'Wallet currency does not match transfer currency');

        const balance = await this.ledger.balance(client, senderWallet.id);
        if (decimalToMinorUnits(balance) < amountToMinorUnits(amount)) throw new AppError('CONFLICT', 'Insufficient wallet funds');
        const transaction = await this.repository.createTransfer(client, {
          userId,
          walletId: senderWallet.id,
          counterpartyWalletId: recipientWallet.id,
          type,
          amount,
          currency,
          reference: randomUUID(),
          idempotencyKey
        });
        if (transaction.status !== 'pending') throw new AppError('INTERNAL_ERROR', 'Transfer could not be created');
        await this.ledger.recordTransfer(client, {
          transactionId: transaction.id,
          debitWalletId: senderWallet.id,
          creditWalletId: recipientWallet.id,
          amount,
          currency,
          kind: type === 'qr_payment' ? 'qr_payment' : 'wallet_transfer'
        });
        await this.repository.markTransferSucceeded(client, transaction.id);
        transaction.status = 'succeeded';
        return { transaction: this.transactionProjection(transaction), recipient: { username: recipient?.username ?? 'unknown', displayName: recipient?.displayName ?? 'Eazy user' } };
      });
    } catch (error) {
      if (error instanceof AppError) throw error;
      if ((error as { code?: string })?.code === '23505') throw new AppError('CONFLICT', 'A duplicate financial operation was rejected');
      if ((error as { code?: string })?.code === '23503') throw new AppError('BAD_REQUEST', 'Financial account relationship is invalid');
      throw error;
    }
  }

  private transactionProjection(transaction: { id: string; type: string; amount: string; currency: string; status: string; reference: string; createdAt: string }): WalletTransactionProjection {
    return { id: transaction.id, type: transaction.type, amount: transaction.amount, currency: transaction.currency, status: transaction.status, reference: transaction.reference, createdAt: transaction.createdAt };
  }

  private scopedKey(userId: string, operation: string, key: string): string {
    return createHash('sha256').update(`${userId}:${operation}:${key}`).digest('hex');
  }
}

function decimalToMinorUnits(value: string): bigint {
  const match = /^(-?)(0|[1-9][0-9]*)(?:\.([0-9]{1,2}))?$/.exec(value);
  if (!match) throw new AppError('INTERNAL_ERROR', 'Wallet balance could not be read');
  const units = BigInt(match[2]!) * 100n + BigInt((match[3] ?? '').padEnd(2, '0') || '0');
  return match[1] === '-' ? -units : units;
}
