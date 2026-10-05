import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import type { TransferRecord, WalletProjection, WalletRepositoryContract, WalletTransactionProjection } from './types.js';

interface WalletRow { id: string; user_id: string; currency: string; status: string; }

const transferProjection = `id, user_id AS "userId", wallet_id AS "walletId", counterparty_wallet_id AS "counterpartyWalletId", type, status,
  amount::numeric(20,2)::text AS amount, trim(currency) AS currency, reference,
  idempotency_key AS "idempotencyKey", order_id AS "orderId", created_at AS "createdAt"`;

export class WalletRepository implements WalletRepositoryContract {
  constructor(private readonly pool: Pool) {}

  async listWallets(userId: string): Promise<WalletProjection[]> {
    const result = await this.pool.query<WalletProjection>(
      `SELECT w.id, trim(w.currency) AS currency, w.status,
        COALESCE(sum(CASE WHEN le.direction = 'credit' THEN le.amount ELSE -le.amount END), 0)::numeric(20,2)::text AS balance
       FROM wallets w LEFT JOIN ledger_entries le ON le.wallet_id = w.id
       WHERE w.user_id = $1 GROUP BY w.id ORDER BY trim(w.currency), w.id LIMIT 100`, [userId]
    );
    return result.rows;
  }

  async createOrGetWallet(client: DbClient, userId: string, currency: string): Promise<{ id: string; userId: string; currency: string; status: string }> {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`wallet-create:${userId}`]);
    await client.query('INSERT INTO wallets (user_id, currency) VALUES ($1, $2) ON CONFLICT (user_id) DO NOTHING', [userId, currency]);
    const result = await client.query<WalletRow>('SELECT id, user_id, trim(currency) AS currency, status FROM wallets WHERE user_id = $1 FOR UPDATE', [userId]);
    const row = result.rows[0];
    if (!row) throw new Error('WALLET_CREATE_FAILED');
    return { id: row.id, userId: row.user_id, currency: row.currency, status: row.status };
  }

  async listTransactions(userId: string, page: number, limit: number): Promise<{ items: WalletTransactionProjection[]; total: number }> {
    const [count, rows] = await Promise.all([
      this.pool.query<{ count: string }>('SELECT count(*)::text AS count FROM transactions WHERE user_id = $1', [userId]),
      this.pool.query<WalletTransactionProjection>(
        `SELECT id, type, amount::numeric(20,2)::text AS amount, trim(currency) AS currency, status, reference, created_at AS "createdAt"
         FROM transactions WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3`,
        [userId, limit, (page - 1) * limit]
      )
    ]);
    return { items: rows.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async getTransaction(userId: string, transactionId: string): Promise<WalletTransactionProjection | null> {
    const result = await this.pool.query<WalletTransactionProjection>(
      `SELECT id, type, amount::numeric(20,2)::text AS amount, trim(currency) AS currency, status, reference, created_at AS "createdAt"
       FROM transactions WHERE id = $1 AND user_id = $2 LIMIT 1`, [transactionId, userId]
    );
    return result.rows[0] ?? null;
  }

  async resolveRecipientByUsername(client: DbClient, username: string): Promise<{ userId: string; username: string; displayName: string } | null> {
    const result = await client.query<{ user_id: string; username: string; display_name: string }>(
      `SELECT u.id AS user_id, p.username, p.display_name
       FROM profiles p JOIN users u ON u.id = p.user_id
       WHERE p.username = $1 AND u.status = 'active' LIMIT 1`, [username.toLowerCase()]
    );
    const row = result.rows[0];
    return row ? { userId: row.user_id, username: row.username, displayName: row.display_name } : null;
  }

  async findWalletForUser(client: DbClient, userId: string): Promise<{ id: string; userId: string; currency: string; status: string } | null> {
    const result = await client.query<WalletRow>('SELECT id, user_id, trim(currency) AS currency, status FROM wallets WHERE user_id = $1 FOR UPDATE', [userId]);
    const row = result.rows[0];
    return row ? { id: row.id, userId: row.user_id, currency: row.currency, status: row.status } : null;
  }

  async lockWallets(client: DbClient, userIds: string[]): Promise<{ id: string; userId: string; currency: string; status: string }[]> {
    const result = await client.query<WalletRow>(
      `SELECT id, user_id, trim(currency) AS currency, status FROM wallets
       WHERE user_id = ANY($1::uuid[]) ORDER BY user_id FOR UPDATE`, [userIds]
    );
    return result.rows.map(row => ({ id: row.id, userId: row.user_id, currency: row.currency, status: row.status }));
  }

  async getBalance(client: DbClient, walletId: string): Promise<string> {
    const result = await client.query<{ balance: string }>(
      `SELECT COALESCE(sum(CASE WHEN direction = 'credit' THEN amount ELSE -amount END), 0)::numeric(20,2)::text AS balance
       FROM ledger_entries WHERE wallet_id = $1`, [walletId]
    );
    return result.rows[0]?.balance ?? '0.00';
  }

  async lockIdempotencyKey(client: DbClient, key: string): Promise<void> {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`financial-idempotency:${key}`]);
  }

  async findByIdempotencyKey(client: DbClient, key: string): Promise<TransferRecord | null> {
    const result = await client.query<TransferRecord>(`SELECT ${transferProjection} FROM transactions WHERE idempotency_key = $1 FOR UPDATE`, [key]);
    return result.rows[0] ?? null;
  }

  async findTransferRecipient(client: DbClient, transactionId: string): Promise<string | null> {
    const result = await client.query<{ user_id: string }>(
      `SELECT w.user_id FROM transactions t JOIN wallets w ON w.id = t.counterparty_wallet_id WHERE t.id = $1 LIMIT 1`, [transactionId]
    );
    return result.rows[0]?.user_id ?? null;
  }

  async createTransfer(client: DbClient, input: { userId: string; walletId: string; counterpartyWalletId: string; type: 'transfer' | 'qr_payment'; amount: string; currency: string; reference: string; idempotencyKey: string }): Promise<TransferRecord> {
    const result = await client.query<TransferRecord>(
      `INSERT INTO transactions (user_id, wallet_id, counterparty_wallet_id, type, status, amount, currency, reference, idempotency_key)
       VALUES ($1, $2, $3, $4, 'pending', $5::numeric(20,2), $6, $7, $8) RETURNING ${transferProjection}`,
      [input.userId, input.walletId, input.counterpartyWalletId, input.type, input.amount, input.currency, input.reference, input.idempotencyKey]
    );
    return result.rows[0]!;
  }

  async markTransferFailed(client: DbClient, transactionId: string): Promise<void> {
    const result = await client.query("UPDATE transactions SET status = 'failed', updated_at = now() WHERE id = $1 AND status = 'pending'", [transactionId]);
    if (result.rowCount !== 1) throw new Error('TRANSFER_STATE_CONFLICT');
  }

  async markTransferSucceeded(client: DbClient, transactionId: string): Promise<void> {
    const result = await client.query("UPDATE transactions SET status = 'succeeded', updated_at = now() WHERE id = $1 AND status = 'pending'", [transactionId]);
    if (result.rowCount !== 1) throw new Error('TRANSFER_STATE_CONFLICT');
  }

  async getTransferById(client: DbClient, transactionId: string): Promise<TransferRecord | null> {
    const result = await client.query<TransferRecord>(`SELECT ${transferProjection} FROM transactions WHERE id = $1 LIMIT 1`, [transactionId]);
    return result.rows[0] ?? null;
  }
}
