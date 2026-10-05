import type { DbClient } from '../../database/client.js';

export interface WalletProjection {
  id: string;
  currency: string;
  status: 'active' | 'frozen' | 'closed';
  balance: string;
}

export interface WalletTransactionProjection {
  id: string;
  type: string;
  amount: string;
  currency: string;
  status: string;
  reference: string;
  createdAt: string;
}

export interface TransferInput {
  recipientUsername: string;
  amount: string;
  currency: string;
}

export interface TransferRecord {
  id: string;
  userId: string;
  walletId: string | null;
  counterpartyWalletId: string | null;
  type: string;
  status: 'pending' | 'succeeded' | 'failed' | 'reversed';
  amount: string;
  currency: string;
  reference: string;
  idempotencyKey: string;
  orderId: string | null;
  createdAt: string;
}

export interface WalletRepositoryContract {
  listWallets(userId: string): Promise<WalletProjection[]>;
  createOrGetWallet(client: DbClient, userId: string, currency: string): Promise<{ id: string; userId: string; currency: string; status: string }>;
  listTransactions(userId: string, page: number, limit: number): Promise<{ items: WalletTransactionProjection[]; total: number }>;
  getTransaction(userId: string, transactionId: string): Promise<WalletTransactionProjection | null>;
  resolveRecipientByUsername(client: DbClient, username: string): Promise<{ userId: string; username: string; displayName: string } | null>;
  findWalletForUser(client: DbClient, userId: string): Promise<{ id: string; userId: string; currency: string; status: string } | null>;
  lockWallets(client: DbClient, userIds: string[]): Promise<{ id: string; userId: string; currency: string; status: string }[]>;
  getBalance(client: DbClient, walletId: string): Promise<string>;
  lockIdempotencyKey(client: DbClient, key: string): Promise<void>;
  findByIdempotencyKey(client: DbClient, key: string): Promise<TransferRecord | null>;
  findTransferRecipient(client: DbClient, transactionId: string): Promise<string | null>;
  createTransfer(client: DbClient, input: { userId: string; walletId: string; counterpartyWalletId: string; type: 'transfer' | 'qr_payment'; amount: string; currency: string; reference: string; idempotencyKey: string }): Promise<TransferRecord>;
  markTransferFailed(client: DbClient, transactionId: string): Promise<void>;
  markTransferSucceeded(client: DbClient, transactionId: string): Promise<void>;
  getTransferById(client: DbClient, transactionId: string): Promise<TransferRecord | null>;
}

export interface TransferResult {
  transaction: WalletTransactionProjection;
  recipient: { username: string; displayName: string };
}
