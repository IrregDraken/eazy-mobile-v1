import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';

export type NotificationType = 'follow' | 'like' | 'comment' | 'message' | 'order' | 'payment' | 'system';
export interface NotificationInput { recipientUserId: string; actorUserId?: string; type: NotificationType; entityType?: string; entityId?: string; title?: string; body?: string; deepLink?: string; }
export interface NotificationProjection { id: string; type: NotificationType; actor: { username: string; displayName: string; avatarUrl: string | null } | null; title: string | null; body: string | null; entityType: string | null; entityId: string | null; isRead: boolean; createdAt: string; }

export class NotificationRepository {
  constructor(private readonly pool: Pool) {}

  async create(client: DbClient, input: NotificationInput): Promise<string | null> {
    if (input.actorUserId && input.actorUserId === input.recipientUserId) return null;
    const allowed = await client.query<{ enabled: boolean }>(
      `SELECT
         CASE $2::text
           WHEN 'follow' THEN COALESCE((SELECT notify_follows FROM user_settings WHERE user_id = $1), true)
           WHEN 'like' THEN COALESCE((SELECT notify_likes FROM user_settings WHERE user_id = $1), true)
           WHEN 'comment' THEN COALESCE((SELECT notify_comments FROM user_settings WHERE user_id = $1), true)
           ELSE true
         END AND ($3::uuid IS NULL OR NOT EXISTS (
           SELECT 1 FROM blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = $3)
             OR (b.blocker_id = $3 AND b.blocked_id = $1)
         )) AS enabled`,
      [input.recipientUserId, input.type, input.actorUserId ?? null]
    );
    if (allowed.rows[0]?.enabled === false) return null;
    const result = await client.query<{ id: string }>(
      `INSERT INTO notifications (user_id, actor_user_id, type, target_type, target_id, title, body, deep_link)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
      [input.recipientUserId, input.actorUserId ?? null, input.type, input.entityType ?? null, input.entityId ?? null, input.title ?? null, input.body ?? null, input.deepLink ?? null]
    );
    return result.rows[0]?.id ?? null;
  }

  async list(userId: string, page: number, limit: number): Promise<{ items: NotificationProjection[]; total: number }> {
    const visible = `n.user_id = $1 AND (n.actor_user_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM blocks b WHERE (b.blocker_id = n.user_id AND b.blocked_id = n.actor_user_id)
        OR (b.blocker_id = n.actor_user_id AND b.blocked_id = n.user_id)
    ))`;
    const count = await this.pool.query<{ count: string }>(`SELECT count(*)::text AS count FROM notifications n WHERE ${visible}`, [userId]);
    const result = await this.pool.query<NotificationProjection>(
      `SELECT n.id, n.type, n.title, n.body, n.target_type AS "entityType", n.target_id AS "entityId", n.is_read AS "isRead", n.created_at AS "createdAt",
        CASE WHEN p.user_id IS NULL THEN NULL ELSE json_build_object('username', p.username, 'displayName', p.display_name, 'avatarUrl', p.avatar_url) END AS actor
       FROM notifications n LEFT JOIN profiles p ON p.user_id = n.actor_user_id
       WHERE ${visible} ORDER BY n.created_at DESC, n.id DESC LIMIT $2 OFFSET $3`, [userId, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async get(userId: string, id: string): Promise<NotificationProjection | null> {
    const result = await this.pool.query<NotificationProjection>(
      `SELECT n.id, n.type, n.title, n.body, n.target_type AS "entityType", n.target_id AS "entityId", n.is_read AS "isRead", n.created_at AS "createdAt",
        CASE WHEN p.user_id IS NULL THEN NULL ELSE json_build_object('username', p.username, 'displayName', p.display_name, 'avatarUrl', p.avatar_url) END AS actor
       FROM notifications n LEFT JOIN profiles p ON p.user_id = n.actor_user_id
       WHERE n.id = $1 AND n.user_id = $2
         AND (n.actor_user_id IS NULL OR NOT EXISTS (
           SELECT 1 FROM blocks b WHERE (b.blocker_id = n.user_id AND b.blocked_id = n.actor_user_id)
             OR (b.blocker_id = n.actor_user_id AND b.blocked_id = n.user_id)
         )) LIMIT 1`, [id, userId]
    );
    return result.rows[0] ?? null;
  }

  async markRead(userId: string, id: string): Promise<boolean> {
    const result = await this.pool.query('UPDATE notifications SET is_read = true WHERE id = $1 AND user_id = $2 RETURNING id', [id, userId]);
    return Boolean(result.rowCount);
  }

  async markAllRead(userId: string): Promise<number> {
    const result = await this.pool.query('UPDATE notifications SET is_read = true WHERE user_id = $1 AND is_read = false RETURNING id', [userId]);
    return result.rowCount ?? 0;
  }

  async unreadCount(userId: string): Promise<number> {
    const result = await this.pool.query<{ count: string }>('SELECT count(*)::text AS count FROM notifications WHERE user_id = $1 AND is_read = false', [userId]);
    return Number(result.rows[0]?.count ?? 0);
  }

  async registerDevice(userId: string, token: string, platform: 'ios' | 'android' | 'web'): Promise<string> {
    const existing = await this.pool.query<{ id: string; user_id: string }>('SELECT id, user_id FROM push_devices WHERE device_token = $1 LIMIT 1', [token]);
    if (existing.rows[0] && existing.rows[0].user_id !== userId) throw new Error('DEVICE_OWNERSHIP');
    if (existing.rows[0]) {
      await this.pool.query('UPDATE push_devices SET platform = $1, is_active = true, revoked_at = NULL, updated_at = now() WHERE id = $2 AND user_id = $3', [platform, existing.rows[0].id, userId]);
      return existing.rows[0].id;
    }
    const result = await this.pool.query<{ id: string }>('INSERT INTO push_devices (user_id, device_token, platform) VALUES ($1, $2, $3) RETURNING id', [userId, token, platform]);
    return result.rows[0]!.id;
  }

  async deleteDevice(userId: string, id: string): Promise<boolean> {
    const result = await this.pool.query('UPDATE push_devices SET is_active = false, revoked_at = now(), updated_at = now() WHERE id = $1 AND user_id = $2 AND is_active = true RETURNING id', [id, userId]);
    return Boolean(result.rowCount);
  }
}
