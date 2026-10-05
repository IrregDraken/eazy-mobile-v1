import type { DbClient } from '../../database/client.js';
import type { LedgerRepositoryContract } from './types.js';

export class LedgerService {
  constructor(private readonly repository: LedgerRepositoryContract) {}

  balance(client: DbClient, walletId: string): Promise<string> {
    return this.repository.getBalance(client, walletId);
  }

  async recordTransfer(client: DbClient, input: {
    transactionId: string;
    debitWalletId: string;
    creditWalletId: string;
    amount: string;
    currency: string;
    kind: 'wallet_transfer' | 'qr_payment';
  }): Promise<void> {
    const prefix = input.kind === 'qr_payment' ? 'qr_payment' : 'wallet_transfer';
    await this.repository.createEntry(client, {
      walletId: input.debitWalletId,
      transactionId: input.transactionId,
      direction: 'debit',
      amount: input.amount,
      currency: input.currency,
      entryType: `${prefix}_debit`,
      idempotencyKey: `${input.transactionId}:debit`
    });
    await this.repository.createEntry(client, {
      walletId: input.creditWalletId,
      transactionId: input.transactionId,
      direction: 'credit',
      amount: input.amount,
      currency: input.currency,
      entryType: `${prefix}_credit`,
      idempotencyKey: `${input.transactionId}:credit`
    });
  }

  async recordWithdrawal(client: DbClient, input: { transactionId: string; walletId: string; amount: string; currency: string }): Promise<void> {
    await this.repository.createEntry(client, {
      walletId: input.walletId,
      transactionId: input.transactionId,
      direction: 'debit',
      amount: input.amount,
      currency: input.currency,
      entryType: 'bank_transfer_debit',
      idempotencyKey: `${input.transactionId}:bank-transfer-debit`
    });
  }

  async createInboundDeposit(client: DbClient, input: { transactionId: string; walletId: string; amount: string; currency: string; providerReference: string }): Promise<void> {
    await this.repository.createEntry(client, {
      walletId: input.walletId,
      transactionId: input.transactionId,
      direction: 'credit',
      amount: input.amount,
      currency: input.currency,
      entryType: 'bank_transfer_deposit',
      idempotencyKey: `${input.transactionId}:bank-transfer-deposit:${input.providerReference}`
    });
  }

  async recordWithdrawalReversal(client: DbClient, input: { transactionId: string; walletId: string; amount: string; currency: string }): Promise<void> {
    await this.repository.createEntry(client, {
      walletId: input.walletId,
      transactionId: input.transactionId,
      direction: 'credit',
      amount: input.amount,
      currency: input.currency,
      entryType: 'bank_transfer_reversal',
      idempotencyKey: `${input.transactionId}:bank-transfer-reversal`
    });
  }
}
