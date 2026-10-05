import type { DbClient } from '../../database/client.js';
import type { BankTransferRepositoryContract, BankTransferRecord } from './transfer-types.js';

const projection = `t.id, t.user_id AS "userId", t.wallet_id AS "walletId", t.type, t.status,
  t.amount::numeric(20,2)::text AS amount, trim(t.currency) AS currency, t.reference,
  t.idempotency_key AS "idempotencyKey", t.provider_reference AS "providerReference",
  b.account_name AS "accountName", b.bank_code AS "bankCode", b.bank_name AS "bankName",
  b.recipient_code AS "recipientCode", b.account_fingerprint AS "accountFingerprint",
  t.created_at AS "createdAt"
  FROM transactions t JOIN bank_transfer_details b ON b.transaction_id = t.id`;

export class BankTransferRepository implements BankTransferRepositoryContract {
  async lockIdempotencyKey(client: DbClient, key: string) {
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`bank-transfer:${key}`]);
  }

  async findByIdempotencyKey(client: DbClient, key: string) {
    const result = await client.query<BankTransferRecord>(`SELECT ${projection} WHERE t.idempotency_key = $1 LIMIT 1 FOR UPDATE`, [key]);
    return result.rows[0] ?? null;
  }

  async findByProviderReference(client: DbClient, providerReference: string) {
    const result = await client.query<BankTransferRecord>(`SELECT ${projection} WHERE t.provider_reference = $1 OR t.reference = $1 LIMIT 1 FOR UPDATE`, [providerReference]);
    return result.rows[0] ?? null;
  }

  async findForUser(client: DbClient, userId: string, transactionId: string) {
    const result = await client.query<BankTransferRecord>(`SELECT ${projection} WHERE t.id = $1 AND t.user_id = $2 LIMIT 1`, [transactionId, userId]);
    return result.rows[0] ?? null;
  }

  async createPending(client: DbClient, input: {
    userId: string; walletId: string; amount: string; currency: string; reference: string; idempotencyKey: string;
    accountName: string; accountFingerprint: string; bankCode: string; bankName?: string;
  }) {
    const transaction = await client.query<{ id: string }>(
      `INSERT INTO transactions (user_id, wallet_id, type, status, amount, currency, reference, idempotency_key)
       VALUES ($1, $2, 'withdrawal', 'pending', $3::numeric(20,2), $4, $5, $6) RETURNING id`,
      [input.userId, input.walletId, input.amount, input.currency, input.reference, input.idempotencyKey]
    );
    const id = transaction.rows[0]!.id;
    await client.query(
      `INSERT INTO bank_transfer_details (transaction_id, bank_code, bank_name, account_name, account_fingerprint)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, input.bankCode, input.bankName ?? null, input.accountName, input.accountFingerprint]
    );
    const result = await client.query<BankTransferRecord>(`SELECT ${projection} WHERE t.id = $1`, [id]);
    return result.rows[0]!;
  }

  async saveRecipient(client: DbClient, transactionId: string, recipientCode: string) {
    const result = await client.query(
      'UPDATE bank_transfer_details SET recipient_code = $2, updated_at = now() WHERE transaction_id = $1',
      [transactionId, recipientCode]
    );
    if (result.rowCount !== 1) throw new Error('BANK_TRANSFER_RECIPIENT_PERSISTENCE_CONFLICT');
  }

  async saveProviderReference(client: DbClient, transactionId: string, providerReference: string) {
    const result = await client.query(
      `UPDATE transactions SET provider_reference = $2, updated_at = now()
       WHERE id = $1 AND status = 'pending'`,
      [transactionId, providerReference]
    );
    if (result.rowCount !== 1) throw new Error('BANK_TRANSFER_REFERENCE_PERSISTENCE_CONFLICT');
    await client.query(
      'UPDATE bank_transfer_details SET provider_reference = $2, updated_at = now() WHERE transaction_id = $1',
      [transactionId, providerReference]
    );
  }

  async settle(client: DbClient, transactionId: string, status: 'succeeded' | 'failed' | 'reversed', providerReference?: string) {
    const current = await this.getTransactionForSettlement(client, transactionId);
    if (!current) return null;
    if (current.status !== 'pending') return current;
    await client.query(
      `UPDATE transactions SET status = $2, provider_reference = COALESCE($3, provider_reference), updated_at = now()
       WHERE id = $1 AND status = 'pending'`,
      [transactionId, status, providerReference ?? null]
    );
    const result = await client.query<BankTransferRecord>(`SELECT ${projection} WHERE t.id = $1`, [transactionId]);
    return result.rows[0] ?? null;
  }

  async getTransactionForSettlement(client: DbClient, transactionId: string) {
    const result = await client.query<BankTransferRecord>(`SELECT ${projection} WHERE t.id = $1 LIMIT 1 FOR UPDATE`, [transactionId]);
    return result.rows[0] ?? null;
  }
}