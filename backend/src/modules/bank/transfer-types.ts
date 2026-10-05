import type { DbClient } from '../../database/client.js';

export interface BankTransferInput {
  accountNumber: string;
  bankCode: string;
  amount: string;
  currency: string;
  accountName: string;
  bankName?: string;
  reason?: string;
}

export interface BankTransferRecord {
  id: string;
  userId: string;
  walletId: string;
  type: 'withdrawal';
  status: 'pending' | 'succeeded' | 'failed' | 'reversed';
  amount: string;
  currency: string;
  reference: string;
  idempotencyKey: string;
  providerReference: string | null;
  accountName: string;
  bankCode: string;
  bankName: string | null;
  recipientCode: string | null;
  accountFingerprint: string;
  createdAt: string;
}

export interface BankTransferRepositoryContract {
  lockIdempotencyKey(client: DbClient, key: string): Promise<void>;
  findByIdempotencyKey(client: DbClient, key: string): Promise<BankTransferRecord | null>;
  findByProviderReference(client: DbClient, providerReference: string): Promise<BankTransferRecord | null>;
  findForUser(client: DbClient, userId: string, transactionId: string): Promise<BankTransferRecord | null>;
  createPending(client: DbClient, input: {
    userId: string; walletId: string; amount: string; currency: string; reference: string; idempotencyKey: string;
    accountName: string; accountFingerprint: string; bankCode: string; bankName?: string;
  }): Promise<BankTransferRecord>;
  saveRecipient(client: DbClient, transactionId: string, recipientCode: string): Promise<void>;
  saveProviderReference(client: DbClient, transactionId: string, providerReference: string): Promise<void>;
  settle(client: DbClient, transactionId: string, status: 'succeeded' | 'failed' | 'reversed', providerReference?: string): Promise<BankTransferRecord | null>;
  getTransactionForSettlement(client: DbClient, transactionId: string): Promise<BankTransferRecord | null>;
}