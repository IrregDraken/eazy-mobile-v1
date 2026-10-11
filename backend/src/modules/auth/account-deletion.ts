import { isIP } from 'node:net';
import type { Pool } from 'pg';
import { withTransaction, type DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { SessionTerminator } from './service.js';

export type DeletionBlockerCode = 'WALLET_BALANCE' | 'PENDING_PAYMENTS' | 'ACTIVE_ORDERS' | 'ACTIVE_SALES';
export interface DeletionBlocker { code: DeletionBlockerCode; message: string }

/** Removes the sign-in identity (Firebase) so the person can no longer authenticate. */
export interface IdentityRemover { deleteIdentity(firebaseUid: string): Promise<void> }
export interface MediaDeleter { deleteObjects(paths: readonly string[]): Promise<{ deleted: number; requested: number }> }

const BLOCKER_MESSAGES: Record<DeletionBlockerCode, string> = {
  WALLET_BALANCE: 'Move or withdraw the money in your Eazy wallet before deleting your account.',
  PENDING_PAYMENTS: 'You have payments that are still being processed. Try again once they have finished.',
  ACTIVE_ORDERS: 'You have orders that are still on their way. Try again once they are completed.',
  ACTIVE_SALES: 'You have sales that still need to be fulfilled. Complete or cancel them first.'
};

type Queryable = Pick<DbClient, 'query'>;

/**
 * Account deletion keeps the financial ledger intact (wallet, transactions, orders) because those records must
 * be retained, but removes or anonymises everything that identifies the person or that they authored.
 * The `users` row stays as a tombstone with status 'deleted' so that a still-valid token can never re-provision it.
 */
export class AccountDeletionService {
  constructor(
    private readonly pool: Pool,
    private readonly identityRemover?: IdentityRemover,
    private readonly terminator?: SessionTerminator,
    private readonly mediaDeleter?: MediaDeleter
  ) {}

  async preflight(userId: string): Promise<{ canDelete: boolean; blockers: DeletionBlocker[] }> {
    const blockers = await this.findBlockers(this.pool, userId);
    return { canDelete: blockers.length === 0, blockers };
  }

  async deleteAccount(userId: string, metadata: { ipAddress?: string } = {}): Promise<{ deleted: true; cleanupPending?: true }> {
    let firebaseUid = '';
    await withTransaction(this.pool, async client => {
      const locked = await client.query<{ firebase_uid: string; email: string | null; status: string }>(
        'SELECT firebase_uid, email, status FROM users WHERE id = $1 FOR UPDATE', [userId]
      );
      const user = locked.rows[0];
      if (!user) throw new AppError('NOT_FOUND', 'Account not found');
      if (user.status === 'deleted') return;
      firebaseUid = user.firebase_uid;

      const blockers = await this.findBlockers(client, userId);
      if (blockers.length) throw new AppError('CONFLICT', blockers[0]!.message, { blockers });

      const mediaKeys = await this.collectOwnedMediaKeys(client, userId);
      await client.query(
        `INSERT INTO account_deletion_jobs (user_id, firebase_uid) VALUES ($1, $2)
         ON CONFLICT (user_id) DO UPDATE SET firebase_uid = EXCLUDED.firebase_uid, updated_at = now()`,
        [userId, user.firebase_uid]
      );
      for (const storageKey of mediaKeys) {
        await client.query(
          `INSERT INTO account_deletion_media (user_id, storage_key) VALUES ($1, $2)
           ON CONFLICT (user_id, storage_key) DO NOTHING`, [userId, storageKey]
        );
      }

      // ---- Content the person created or took part in ------------------------------------------------------
      await client.query('DELETE FROM likes WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM saves WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM comments WHERE author_id = $1', [userId]);
      await client.query('DELETE FROM posts WHERE author_id = $1', [userId]);
      await client.query('DELETE FROM follows WHERE follower_id = $1 OR followee_id = $1', [userId]);
      await client.query('DELETE FROM blocks WHERE blocker_id = $1 OR blocked_id = $1', [userId]);

      // ---- Chat: other people keep their thread, but nothing the person wrote survives --------------------
      await client.query('DELETE FROM message_attachments WHERE message_id IN (SELECT id FROM messages WHERE sender_id = $1)', [userId]);
      await client.query(
        `UPDATE messages SET body = NULL, status = 'deleted', deleted_at = COALESCE(deleted_at, now()), updated_at = now()
         WHERE sender_id = $1`, [userId]
      );
      await client.query('DELETE FROM message_reactions WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM message_reads WHERE user_id = $1', [userId]);
      await client.query('UPDATE conversation_members SET left_at = COALESCE(left_at, now()) WHERE user_id = $1', [userId]);

      // ---- Marketplace --------------------------------------------------------------------------------------
      await client.query('DELETE FROM cart_items WHERE product_id IN (SELECT id FROM products WHERE seller_id = $1)', [userId]);
      await client.query(`UPDATE products SET status = 'archived', updated_at = now() WHERE seller_id = $1 AND status <> 'archived'`, [userId]);
      await client.query('DELETE FROM carts WHERE buyer_id = $1', [userId]);
      await client.query(`UPDATE orders SET status = 'cancelled', updated_at = now() WHERE buyer_id = $1 AND status = 'pending'`, [userId]);

      // ---- Money: records stay, the ability to use them goes ------------------------------------------------
      await client.query(`UPDATE qr_codes SET status = 'revoked' WHERE owner_id = $1 AND status = 'active'`, [userId]);
      await client.query(`UPDATE wallet_virtual_accounts SET status = 'suspended', updated_at = now() WHERE user_id = $1 AND status <> 'suspended'`, [userId]);
      await client.query(`UPDATE wallets SET status = 'closed', updated_at = now() WHERE user_id = $1 AND status <> 'closed'`, [userId]);

      // ---- Personal data and activity ---------------------------------------------------------------------
      await client.query('DELETE FROM notifications WHERE user_id = $1', [userId]);
      await client.query('UPDATE notifications SET actor_user_id = NULL WHERE actor_user_id = $1', [userId]);
      await client.query('DELETE FROM push_devices WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM assist_sessions WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM translation_requests WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM user_settings WHERE user_id = $1', [userId]);
      await client.query('DELETE FROM verification_codes WHERE user_id = $1', [userId]);
      if (user.email) await client.query('DELETE FROM email_verification_challenges WHERE lower(email) = lower($1)', [user.email]);
      await client.query('UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);

      await client.query(
        `UPDATE profiles SET username = 'deleted_' || substr(replace(user_id::text, '-', ''), 1, 12), display_name = 'Deleted user',
           bio = NULL, avatar_url = NULL, country_code = NULL, first_name = NULL, last_name = NULL, date_of_birth = NULL, updated_at = now()
         WHERE user_id = $1`, [userId]
      );
      await client.query(
        `UPDATE users SET status = 'deleted', email = NULL, phone = NULL, email_verified_at = NULL, updated_at = now() WHERE id = $1`, [userId]
      );
      await client.query(
        `INSERT INTO security_events (user_id, event_type, severity, ip_address, metadata) VALUES ($1, 'account_deleted', 'info', $2::inet, '{}'::jsonb)`,
        [userId, validIp(metadata.ipAddress)]
      );

    });
    const cleanup = await this.finishExternalCleanup(userId, firebaseUid);
    this.terminator?.terminateUserSessions(userId);
    return cleanup.pending ? { deleted: true, cleanupPending: true } : { deleted: true };
  }

  /** Retries media and Firebase cleanup without reopening a deleted account. */
  async retryCleanup(userId: string): Promise<{ pending: boolean }> { return this.finishExternalCleanup(userId); }

  private async collectOwnedMediaKeys(client: DbClient, userId: string): Promise<string[]> {
    const result = await client.query<{ storage_key: string }>(
      `SELECT storage_key FROM (
         SELECT p.avatar_url AS storage_key FROM profiles p WHERE p.user_id = $1 AND p.avatar_url LIKE $2
         UNION ALL SELECT pm.storage_key FROM post_media pm JOIN posts p ON p.id = pm.post_id WHERE p.author_id = $1 AND pm.storage_key LIKE $2
         UNION ALL SELECT pm.storage_key FROM product_media pm JOIN products p ON p.id = pm.product_id WHERE p.seller_id = $1 AND pm.storage_key LIKE $2
         UNION ALL SELECT ma.storage_key FROM message_attachments ma JOIN messages m ON m.id = ma.message_id WHERE m.sender_id = $1 AND ma.storage_key LIKE $2
       ) owned WHERE storage_key IS NOT NULL AND storage_key <> '' AND storage_key !~ '(^/|\\.\\.|\\\\)'`,
      [userId, `${userId}/%`]
    );
    return [...new Set(result.rows.map(row => row.storage_key))];
  }

  private async finishExternalCleanup(userId: string, firebaseUidHint?: string): Promise<{ pending: boolean }> {
    const claimed = await this.claimCleanup(userId, firebaseUidHint);
    if (!claimed) return { pending: Boolean(firebaseUidHint) };
    try {
      if (claimed.mediaKeys.length) {
        if (!this.mediaDeleter) throw new Error('Media storage cleanup is not configured');
        const result = await this.mediaDeleter.deleteObjects(claimed.mediaKeys);
        if (result.requested !== claimed.mediaKeys.length || result.deleted !== claimed.mediaKeys.length) {
          throw new Error('Media storage cleanup returned an incomplete deletion result');
        }
        await this.pool.query(
          `UPDATE account_deletion_media SET status = 'deleted', last_error = NULL, updated_at = now()
           WHERE user_id = $1 AND storage_key = ANY($2::text[]) AND status <> 'deleted'`,
          [userId, claimed.mediaKeys]
        );
      }
      if (!claimed.identityDeleted) {
        if (!this.identityRemover) throw new Error('Firebase identity cleanup is not configured');
        await this.identityRemover.deleteIdentity(claimed.firebaseUid);
        await this.pool.query(`UPDATE account_deletion_jobs SET identity_deleted = true, status = 'complete', last_error = NULL, updated_at = now() WHERE user_id = $1`, [userId]);
      } else {
        await this.pool.query(`UPDATE account_deletion_jobs SET status = 'complete', last_error = NULL, updated_at = now() WHERE user_id = $1`, [userId]);
      }
      return { pending: false };
    } catch (error) {
      const message = error instanceof Error ? error.message.slice(0, 500) : 'External deletion failed';
      await this.pool.query(`UPDATE account_deletion_media SET status = 'failed', last_error = $2, updated_at = now() WHERE user_id = $1 AND status <> 'deleted'`, [userId, message]);
      await this.pool.query(`UPDATE account_deletion_jobs SET status = 'failed', last_error = $2, updated_at = now() WHERE user_id = $1`, [userId, message]);
      return { pending: true };
    }
  }

  private async claimCleanup(userId: string, firebaseUidHint?: string): Promise<{ firebaseUid: string; identityDeleted: boolean; mediaKeys: string[] } | null> {
    return withTransaction(this.pool, async client => {
      const result = await client.query<{ firebase_uid: string; identity_deleted: boolean; status: string; updated_at: string }>(
        `SELECT firebase_uid, identity_deleted, status, updated_at FROM account_deletion_jobs WHERE user_id = $1 FOR UPDATE`, [userId]
      );
      const job = result.rows[0];
      if (!job) return null;
      if (job.status === 'running' && Date.now() - Date.parse(job.updated_at) < 10 * 60 * 1000) return null;
      const media = await client.query<{ storage_key: string }>(
        `SELECT storage_key FROM account_deletion_media WHERE user_id = $1 AND status <> 'deleted' ORDER BY id`, [userId]
      );
      await client.query(`UPDATE account_deletion_jobs SET status = 'running', attempts = attempts + 1, updated_at = now() WHERE user_id = $1`, [userId]);
      await client.query(`UPDATE account_deletion_media SET status = 'pending', attempts = attempts + 1, updated_at = now() WHERE user_id = $1 AND status <> 'deleted'`, [userId]);
      return { firebaseUid: job.firebase_uid || firebaseUidHint || '', identityDeleted: job.identity_deleted, mediaKeys: media.rows.map(row => row.storage_key) };
    });
  }

  private async findBlockers(db: Queryable, userId: string): Promise<DeletionBlocker[]> {
    const result = await db.query<{ balance: string; pending: string; orders: string; sales: string }>(
      `SELECT
         COALESCE((SELECT sum(CASE WHEN le.direction = 'credit' THEN le.amount ELSE -le.amount END)
                   FROM ledger_entries le JOIN wallets w ON w.id = le.wallet_id WHERE w.user_id = $1), 0)::text AS balance,
         (SELECT count(*) FROM transactions t WHERE t.user_id = $1 AND t.status = 'pending'
            AND (t.type <> 'deposit' OR t.created_at > now() - interval '24 hours'))::text AS pending,
         (SELECT count(*) FROM orders o WHERE o.buyer_id = $1 AND o.status IN ('paid', 'processing', 'shipped'))::text AS orders,
         (SELECT count(DISTINCT oi.order_id) FROM order_items oi JOIN orders o ON o.id = oi.order_id
            WHERE oi.seller_id = $1 AND o.status IN ('paid', 'processing', 'shipped'))::text AS sales`, [userId]
    );
    const row = result.rows[0];
    const blockers: DeletionBlocker[] = [];
    if (row && Number(row.balance) !== 0) blockers.push({ code: 'WALLET_BALANCE', message: BLOCKER_MESSAGES.WALLET_BALANCE });
    if (row && Number(row.pending) > 0) blockers.push({ code: 'PENDING_PAYMENTS', message: BLOCKER_MESSAGES.PENDING_PAYMENTS });
    if (row && Number(row.orders) > 0) blockers.push({ code: 'ACTIVE_ORDERS', message: BLOCKER_MESSAGES.ACTIVE_ORDERS });
    if (row && Number(row.sales) > 0) blockers.push({ code: 'ACTIVE_SALES', message: BLOCKER_MESSAGES.ACTIVE_SALES });
    return blockers;
  }
}

function validIp(value?: string): string | null {
  return value && isIP(value) ? value : null;
}
