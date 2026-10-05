import { isIP } from 'node:net';
import type { Pool } from 'pg';
import { withTransaction, type DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { SessionTerminator } from './service.js';

export type DeletionBlockerCode = 'WALLET_BALANCE' | 'PENDING_PAYMENTS' | 'ACTIVE_ORDERS' | 'ACTIVE_SALES';
export interface DeletionBlocker { code: DeletionBlockerCode; message: string }

/** Removes the sign-in identity (Firebase) so the person can no longer authenticate. */
export interface IdentityRemover { deleteIdentity(firebaseUid: string): Promise<void> }

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
    private readonly terminator?: SessionTerminator
  ) {}

  async preflight(userId: string): Promise<{ canDelete: boolean; blockers: DeletionBlocker[] }> {
    const blockers = await this.findBlockers(this.pool, userId);
    return { canDelete: blockers.length === 0, blockers };
  }

  async deleteAccount(userId: string, metadata: { ipAddress?: string } = {}): Promise<{ deleted: true }> {
    await withTransaction(this.pool, async client => {
      const locked = await client.query<{ firebase_uid: string; email: string | null; status: string }>(
        'SELECT firebase_uid, email, status FROM users WHERE id = $1 FOR UPDATE', [userId]
      );
      const user = locked.rows[0];
      if (!user) throw new AppError('NOT_FOUND', 'Account not found');
      if (user.status === 'deleted') return;

      const blockers = await this.findBlockers(client, userId);
      if (blockers.length) throw new AppError('CONFLICT', blockers[0]!.message, { blockers });

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

      // Last step before COMMIT: if the identity cannot be removed, everything above rolls back and the person can retry.
      await this.identityRemover?.deleteIdentity(user.firebase_uid);
    });
    this.terminator?.terminateUserSessions(userId);
    return { deleted: true };
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
