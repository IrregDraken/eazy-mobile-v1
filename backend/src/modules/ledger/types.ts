import type { DbClient } from '../../database/client.js';

export interface LedgerTransferEntry {
  walletId: string;
  transactionId: string;
  direction: 'credit' | 'debit';
  amount: string;
  currency: string;
  entryType: string;
  idempotencyKey: string;
}

export interface LedgerRepositoryContract {
  getBalance(client: DbClient, walletId: string): Promise<string>;
  createEntry(client: DbClient, entry: LedgerTransferEntry): Promise<void>;
}
