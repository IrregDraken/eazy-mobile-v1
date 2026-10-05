import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import type { VirtualAccountProviderPayload, VirtualAccountRecord } from './virtual-account-types.js';

const projection = `user_id AS "userId", wallet_id AS "walletId", provider,
  provider_customer_code AS "customerCode", provider_account_id AS "accountId",
  account_number AS "accountNumber", account_name AS "accountName", bank_name AS "bankName",
  bank_slug AS "bankSlug", trim(currency) AS currency, status, consented_at AS "consentedAt",
  failure_reason AS "failureReason"
  FROM wallet_virtual_accounts`;

export class VirtualAccountRepository {
  constructor(private readonly pool: Pool) {}

  async getForUser(client: DbClient, userId: string): Promise<VirtualAccountRecord | null> {
    const result = await client.query<VirtualAccountRecord>(`SELECT ${projection} WHERE user_id = $1 LIMIT 1`, [userId]);
    return result.rows[0] ?? null;
  }

  async createPending(client: DbClient, input: { userId: string; walletId: string; provider: string; currency: string }): Promise<VirtualAccountRecord> {
    const result = await client.query<VirtualAccountRecord>(
      `INSERT INTO wallet_virtual_accounts (user_id, wallet_id, provider, currency, status, consented_at)
       VALUES ($1, $2, $3, $4, 'pending', now())
       ON CONFLICT (user_id) DO UPDATE SET consented_at = now(), updated_at = now()
       RETURNING user_id AS "userId", wallet_id AS "walletId", provider, provider_customer_code AS "customerCode",
         provider_account_id AS "accountId", account_number AS "accountNumber", account_name AS "accountName",
         bank_name AS "bankName", bank_slug AS "bankSlug", trim(currency) AS currency, status,
         consented_at AS "consentedAt", failure_reason AS "failureReason"`,
      [input.userId, input.walletId, input.provider, input.currency]
    );
    return result.rows[0]!;
  }

  async saveProviderState(client: DbClient, userId: string, state: VirtualAccountProviderPayload): Promise<VirtualAccountRecord | null> {
    const result = await client.query<VirtualAccountRecord>(
      `UPDATE wallet_virtual_accounts SET
         provider_customer_code = COALESCE($2, provider_customer_code),
         provider_account_id = COALESCE($3, provider_account_id),
         account_number = COALESCE($4, account_number),
         account_name = COALESCE($5, account_name),
         bank_name = COALESCE($6, bank_name),
         bank_slug = COALESCE($7, bank_slug),
         status = $8,
         failure_reason = $9,
         updated_at = now()
       WHERE user_id = $1
       RETURNING user_id AS "userId", wallet_id AS "walletId", provider, provider_customer_code AS "customerCode",
         provider_account_id AS "accountId", account_number AS "accountNumber", account_name AS "accountName",
         bank_name AS "bankName", bank_slug AS "bankSlug", trim(currency) AS currency, status,
         consented_at AS "consentedAt", failure_reason AS "failureReason"`,
      [userId, state.customerCode ?? null, state.accountId ?? null, state.accountNumber ?? null, state.accountName ?? null, state.bankName ?? null, state.bankSlug ?? null, state.status, state.failureReason ?? null]
    );
    return result.rows[0] ?? null;
  }

  async findByCustomerCode(client: DbClient, provider: string, customerCode: string): Promise<VirtualAccountRecord | null> {
    const result = await client.query<VirtualAccountRecord>(`SELECT ${projection} WHERE provider = $1 AND provider_customer_code = $2 LIMIT 1`, [provider, customerCode]);
    return result.rows[0] ?? null;
  }

  async findByAccountNumber(client: DbClient, provider: string, accountNumber: string): Promise<VirtualAccountRecord | null> {
    const result = await client.query<VirtualAccountRecord>(`SELECT ${projection} WHERE provider = $1 AND account_number = $2 LIMIT 1`, [provider, accountNumber]);
    return result.rows[0] ?? null;
  }

  async findByUser(userId: string): Promise<VirtualAccountRecord | null> {
    const result = await this.pool.query<VirtualAccountRecord>(`SELECT ${projection} WHERE user_id = $1 LIMIT 1`, [userId]);
    return result.rows[0] ?? null;
  }
}