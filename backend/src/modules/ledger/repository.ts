import type { DbClient } from '../../database/client.js';
import type { LedgerRepositoryContract, LedgerTransferEntry } from './types.js';

export class LedgerRepository implements LedgerRepositoryContract {
  async getBalance(client: DbClient, walletId: string): Promise<string> {
    const result = await client.query<{ balance: string }>(
      `SELECT COALESCE(sum(CASE WHEN direction = 'credit' THEN amount ELSE -amount END), 0)::text AS balance
       FROM ledger_entries WHERE wallet_id = $1`, [walletId]
    );
    return result.rows[0]?.balance ?? '0';
  }

  async createEntry(client: DbClient, entry: LedgerTransferEntry): Promise<void> {
    await client.query(
      `INSERT INTO ledger_entries (wallet_id, transaction_id, direction, amount, currency, entry_type, idempotency_key)
       VALUES ($1, $2, $3, $4::numeric(20,2), $5, $6, $7)`,
      [entry.walletId, entry.transactionId, entry.direction, entry.amount, entry.currency, entry.entryType, entry.idempotencyKey]
    );
  }
}
