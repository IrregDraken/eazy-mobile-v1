import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import type { PaymentIntentRecord, PaymentRepositoryContract } from './types.js';

export class PaymentRepository implements PaymentRepositoryContract {
  constructor(private readonly pool: Pool) {}

  async lockIdempotencyKey(client: DbClient, idempotencyKey: string): Promise<void> {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`payment-init:${idempotencyKey}`]);
  }

  async findByIdempotencyKey(client: DbClient, idempotencyKey: string): Promise<PaymentIntentRecord | null> {
    const result = await client.query<PaymentIntentRecord>(
      `SELECT t.id, t.user_id AS "userId", t.wallet_id AS "walletId", t.type, t.status,
        t.amount::numeric(20,2)::text AS amount, trim(t.currency) AS currency, t.reference,
        t.idempotency_key AS "idempotencyKey", t.order_id AS "orderId",
        pa.provider AS "providerName", pa.provider_reference AS "providerReference", pa.id AS "attemptId"
       FROM transactions t JOIN payment_attempts pa ON pa.transaction_id = t.id
       WHERE t.idempotency_key = $1 LIMIT 1 FOR UPDATE OF t, pa`, [idempotencyKey]
    );
    return result.rows[0] ?? null;
  }

  async findOrderForBuyer(client: DbClient, orderId: string, userId: string): Promise<{ id: string; status: string; currency: string; totalAmount: string } | null> {
    const result = await client.query<{ id: string; status: string; currency: string; totalAmount: string }>(
      `SELECT id, status, trim(currency) AS currency, total_amount::numeric(20,2)::text AS "totalAmount"
       FROM orders WHERE id = $1 AND buyer_id = $2 FOR UPDATE`, [orderId, userId]
    );
    return result.rows[0] ?? null;
  }

  async findDepositWallet(client: DbClient, userId: string, currency: string): Promise<{ id: string; status: string; currency: string } | null> {
    await client.query('INSERT INTO wallets (user_id, currency) VALUES ($1, $2) ON CONFLICT (user_id) DO NOTHING', [userId, currency]);
    const result = await client.query<{ id: string; status: string; currency: string }>(
      'SELECT id, status, trim(currency) AS currency FROM wallets WHERE user_id = $1 FOR UPDATE', [userId]
    );
    return result.rows[0] ?? null;
  }

  async createIntent(client: DbClient, input: {
    id: string; attemptId: string; userId: string; walletId: string | null; type: 'deposit' | 'purchase'; amount: string; currency: string;
    reference: string; idempotencyKey: string; orderId: string | null; providerName: string; attemptIdempotencyKey: string;
  }): Promise<PaymentIntentRecord> {
    const transaction = await client.query<{ id: string }>(
      `INSERT INTO transactions (id, user_id, wallet_id, type, status, amount, currency, reference, idempotency_key, order_id)
       VALUES ($1, $2, $3, $4, 'pending', $5::numeric(20,2), $6, $7, $8, $9) RETURNING id`,
      [input.id, input.userId, input.walletId, input.type, input.amount, input.currency, input.reference, input.idempotencyKey, input.orderId]
    );
    const transactionId = transaction.rows[0]!.id;
    const attempt = await client.query<{ id: string }>(
      `INSERT INTO payment_attempts (id, transaction_id, provider, status, amount, currency, idempotency_key)
       VALUES ($1, $2, $3, 'pending', $4::numeric(20,2), $5, $6) RETURNING id`,
      [input.attemptId, transactionId, input.providerName, input.amount, input.currency, input.attemptIdempotencyKey]
    );
    return {
      id: transactionId, userId: input.userId, walletId: input.walletId, type: input.type, status: 'pending', amount: input.amount,
      currency: input.currency, reference: input.reference, idempotencyKey: input.idempotencyKey, orderId: input.orderId,
      providerName: input.providerName, providerReference: null, attemptId: attempt.rows[0]!.id
    };
  }

  async saveProviderReference(client: DbClient, transactionId: string, attemptId: string, providerReference: string): Promise<boolean> {
    const attempt = await client.query(
      `UPDATE payment_attempts SET provider_reference = $3, updated_at = now()
       WHERE id = $1 AND transaction_id = $2 AND status = 'pending'`, [attemptId, transactionId, providerReference]
    );
    const transaction = await client.query(
      `UPDATE transactions SET provider_reference = $2, updated_at = now()
       WHERE id = $1 AND status = 'pending'`, [transactionId, providerReference]
    );
    if (attempt.rowCount !== 1 || transaction.rowCount !== 1) throw new Error('PAYMENT_REFERENCE_PERSISTENCE_CONFLICT');
    return true;
  }

  async settleProviderPayment(client: DbClient, transactionId: string, providerReference: string, amount: string, currency: string): Promise<boolean> {
    const locked = await client.query<{ user_id: string; wallet_id: string | null; type: string; order_id: string | null; amount: string; currency: string; status: string }>(
      `SELECT user_id, wallet_id, type, order_id, amount::numeric(20,2)::text AS amount, trim(currency) AS currency, status
       FROM transactions WHERE id = $1 FOR UPDATE`, [transactionId]
    );
    const transaction = locked.rows[0];
    if (!transaction) return false;
    if (transaction.status === 'succeeded') return true;
    if (transaction.status !== 'pending' || transaction.amount !== amount || transaction.currency !== currency) return false;
    await client.query(`UPDATE transactions SET status = 'succeeded', provider_reference = $2, updated_at = now() WHERE id = $1 AND status = 'pending'`, [transactionId, providerReference]);
    await client.query(`UPDATE payment_attempts SET status = 'succeeded', provider_reference = $2, updated_at = now() WHERE transaction_id = $1 AND status = 'pending'`, [transactionId, providerReference]);
    if (transaction.type === 'deposit' && transaction.wallet_id) {
      await client.query(`INSERT INTO ledger_entries (wallet_id, transaction_id, direction, amount, currency, entry_type, idempotency_key)
        VALUES ($1, $2, 'credit', $3::numeric(20,2), $4, 'external_payment_credit', $2 || ':external-payment-credit')
        ON CONFLICT (idempotency_key) DO NOTHING`, [transaction.wallet_id, transactionId, amount, currency]);
    }
    if (transaction.type === 'purchase' && transaction.order_id) {
      await client.query("UPDATE orders SET status = 'paid', updated_at = now() WHERE id = $1 AND status = 'pending'", [transaction.order_id]);
    }
    return true;
  }

  async getByIdForUser(userId: string, transactionId: string): Promise<PaymentIntentRecord | null> {
    const result = await this.pool.query<PaymentIntentRecord>(
      `SELECT t.id, t.user_id AS "userId", t.wallet_id AS "walletId", t.type, t.status,
        t.amount::numeric(20,2)::text AS amount, trim(t.currency) AS currency, t.reference,
        t.idempotency_key AS "idempotencyKey", t.order_id AS "orderId",
        pa.provider AS "providerName", pa.provider_reference AS "providerReference", pa.id AS "attemptId"
       FROM transactions t JOIN payment_attempts pa ON pa.transaction_id = t.id
       WHERE t.id = $1 AND t.user_id = $2 LIMIT 1`, [transactionId, userId]
    );
    return result.rows[0] ?? null;
  }

  async getByProviderReference(providerReference: string): Promise<PaymentIntentRecord | null> {
    const result = await this.pool.query<PaymentIntentRecord>(
      `SELECT t.id, t.user_id AS "userId", t.wallet_id AS "walletId", t.type, t.status,
        t.amount::numeric(20,2)::text AS amount, trim(t.currency) AS currency, t.reference,
        t.idempotency_key AS "idempotencyKey", t.order_id AS "orderId",
        pa.provider AS "providerName", pa.provider_reference AS "providerReference", pa.id AS "attemptId"
       FROM transactions t JOIN payment_attempts pa ON pa.transaction_id = t.id
       WHERE pa.provider_reference = $1 LIMIT 1`, [providerReference]
    );
    return result.rows[0] ?? null;
  }
}
