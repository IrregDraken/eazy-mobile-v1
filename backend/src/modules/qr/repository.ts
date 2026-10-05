import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import type { QrRecord, QrRepositoryContract } from './types.js';

export class QrRepository implements QrRepositoryContract {
  constructor(private readonly pool: Pool) {}

  async create(client: DbClient, input: { ownerId: string; codeHash: string; expiresAt: string }): Promise<{ id: string; createdAt: string } | null> {
    const result = await client.query<{ id: string; createdAt: string }>(
      `INSERT INTO qr_codes (owner_id, code_hash, status, expires_at)
       SELECT u.id, $2, 'active', $3
       FROM users u JOIN profiles p ON p.user_id = u.id
       WHERE u.id = $1 AND u.status = 'active'
       RETURNING id, created_at AS "createdAt"`, [input.ownerId, input.codeHash, input.expiresAt]
    );
    return result.rows[0] ?? null;
  }

  async resolve(codeHash: string): Promise<QrRecord | null> {
    const result = await this.pool.query<QrRecord>(
      `SELECT q.id, q.owner_id AS "ownerId", p.username, p.display_name AS "displayName", q.status, q.expires_at AS "expiresAt"
       FROM qr_codes q JOIN users u ON u.id = q.owner_id JOIN profiles p ON p.user_id = q.owner_id
       WHERE q.code_hash = $1 AND q.status = 'active' AND u.status = 'active'
         AND (q.expires_at IS NULL OR q.expires_at > now()) LIMIT 1`, [codeHash]
    );
    return result.rows[0] ?? null;
  }

  async resolveForPayment(client: DbClient, codeHash: string, allowInactive: boolean): Promise<QrRecord | null> {
    const result = await client.query<QrRecord>(
      `SELECT q.id, q.owner_id AS "ownerId", p.username, p.display_name AS "displayName", q.status, q.expires_at AS "expiresAt"
       FROM qr_codes q JOIN users u ON u.id = q.owner_id JOIN profiles p ON p.user_id = q.owner_id
       WHERE q.code_hash = $1 AND u.status = 'active'
         AND ($2::boolean OR (q.status = 'active' AND (q.expires_at IS NULL OR q.expires_at > now())))
       LIMIT 1 FOR UPDATE OF q`, [codeHash, allowInactive]
    );
    return result.rows[0] ?? null;
  }

  async revoke(ownerId: string, qrId: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE qr_codes SET status = 'revoked' WHERE id = $1 AND owner_id = $2 AND status = 'active'`, [qrId, ownerId]
    );
    return result.rowCount === 1;
  }
}
