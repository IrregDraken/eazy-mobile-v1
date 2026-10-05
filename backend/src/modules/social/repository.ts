import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import { lockUserPair } from './pair-lock.js';

export interface SocialProfile {
  username: string;
  displayName: string;
  avatarUrl: string | null;
}

export class SocialRepository {
  constructor(private readonly pool: Pool) {}

  async targetByUsername(client: Pool | DbClient, username: string): Promise<{ id: string; username: string } | null> {
    const result = await client.query<{ id: string; username: string }>('SELECT u.id, p.username FROM users u JOIN profiles p ON p.user_id = u.id WHERE p.username = $1 AND u.status = \'active\' LIMIT 1', [username.toLowerCase()]);
    return result.rows[0] ?? null;
  }

  async targetById(client: Pool | DbClient, userId: string): Promise<{ id: string; username: string } | null> {
    const result = await client.query<{ id: string; username: string }>(
      `SELECT u.id, p.username FROM users u JOIN profiles p ON p.user_id = u.id
       WHERE u.id = $1 AND u.status = 'active' LIMIT 1`, [userId]
    );
    return result.rows[0] ?? null;
  }

  async isBlocked(client: Pool | DbClient, firstUserId: string, secondUserId: string): Promise<boolean> {
    const result = await client.query<{ exists: boolean }>(
      'SELECT EXISTS (SELECT 1 FROM blocks WHERE (blocker_id = $1 AND blocked_id = $2) OR (blocker_id = $2 AND blocked_id = $1)) AS exists',
      [firstUserId, secondUserId]
    );
    return Boolean(result.rows[0]?.exists);
  }

  async follow(client: DbClient, followerId: string, followeeId: string): Promise<boolean> {
    const result = await client.query('INSERT INTO follows (follower_id, followee_id) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING follower_id', [followerId, followeeId]);
    return Boolean(result.rowCount);
  }

  async unfollow(client: DbClient, followerId: string, followeeId: string): Promise<boolean> {
    const result = await client.query('DELETE FROM follows WHERE follower_id = $1 AND followee_id = $2 RETURNING follower_id', [followerId, followeeId]);
    return Boolean(result.rowCount);
  }

  async block(client: DbClient, blockerId: string, blockedId: string): Promise<boolean> {
    await lockUserPair(client, blockerId, blockedId);
    const result = await client.query('INSERT INTO blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING blocker_id', [blockerId, blockedId]);
    await client.query('DELETE FROM follows WHERE (follower_id = $1 AND followee_id = $2) OR (follower_id = $2 AND followee_id = $1)', [blockerId, blockedId]);
    return Boolean(result.rowCount);
  }

  async unblock(client: DbClient, blockerId: string, blockedId: string): Promise<boolean> {
    const result = await client.query('DELETE FROM blocks WHERE blocker_id = $1 AND blocked_id = $2 RETURNING blocker_id', [blockerId, blockedId]);
    return Boolean(result.rowCount);
  }

  async relationship(client: Pool | DbClient, currentUserId: string, targetUserId: string) {
    const result = await client.query<{ following: boolean; followed_by: boolean; blocked: boolean; blocked_by: boolean }>(
      `SELECT
        EXISTS (SELECT 1 FROM follows WHERE follower_id = $1 AND followee_id = $2) AS following,
        EXISTS (SELECT 1 FROM follows WHERE follower_id = $2 AND followee_id = $1) AS followed_by,
        EXISTS (SELECT 1 FROM blocks WHERE blocker_id = $1 AND blocked_id = $2) AS blocked,
        EXISTS (SELECT 1 FROM blocks WHERE blocker_id = $2 AND blocked_id = $1) AS blocked_by`,
      [currentUserId, targetUserId]
    );
    return result.rows[0] ?? { following: false, followed_by: false, blocked: false, blocked_by: false };
  }

  async list(client: Pool, direction: 'followers' | 'following', username: string, page: number, limit: number, viewerId?: string): Promise<{ items: SocialProfile[]; total: number }> {
    const joinColumn = direction === 'followers' ? 'f.followee_id' : 'f.follower_id';
    const selectedColumn = direction === 'followers' ? 'f.follower_id' : 'f.followee_id';
    const where = `target.username = $1 AND ($2::uuid IS NULL OR NOT EXISTS (
      SELECT 1 FROM blocks b WHERE (b.blocker_id = $2 AND b.blocked_id = ${selectedColumn})
        OR (b.blocker_id = ${selectedColumn} AND b.blocked_id = $2)
    ))`;
    const count = await client.query<{ count: string }>(`SELECT count(*)::text AS count FROM follows f JOIN profiles target ON target.user_id = ${joinColumn} WHERE ${where}`, [username, viewerId ?? null]);
    const result = await client.query<SocialProfile>(
      `SELECT p.username, p.display_name AS "displayName", p.avatar_url AS "avatarUrl"
       FROM follows f JOIN profiles target ON target.user_id = ${joinColumn}
       JOIN profiles p ON p.user_id = ${selectedColumn}
       WHERE ${where} ORDER BY f.created_at DESC, p.username ASC LIMIT $3 OFFSET $4`,
      [username, viewerId ?? null, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async blocks(client: Pool, userId: string, page: number, limit: number): Promise<{ items: SocialProfile[]; total: number }> {
    const count = await client.query<{ count: string }>('SELECT count(*)::text AS count FROM blocks WHERE blocker_id = $1', [userId]);
    const result = await client.query<SocialProfile>(
      `SELECT p.username, p.display_name AS "displayName", p.avatar_url AS "avatarUrl"
       FROM blocks b JOIN profiles p ON p.user_id = b.blocked_id
       WHERE b.blocker_id = $1 ORDER BY b.created_at DESC, p.username ASC LIMIT $2 OFFSET $3`,
      [userId, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async search(client: Pool, userId: string, query: string, page: number, limit: number): Promise<{ items: SocialProfile[]; total: number }> {
    const pattern = `${query.toLowerCase()}%`;
    const where = `u.status = 'active' AND p.user_id <> $1 AND (lower(p.username) LIKE $2 OR lower(p.display_name) LIKE $2)
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = p.user_id) OR (b.blocker_id = p.user_id AND b.blocked_id = $1))`;
    const count = await client.query<{ count: string }>(`SELECT count(*)::text AS count FROM users u JOIN profiles p ON p.user_id = u.id WHERE ${where}`, [userId, pattern]);
    const result = await client.query<SocialProfile>(
      `SELECT p.username, p.display_name AS "displayName", p.avatar_url AS "avatarUrl" FROM users u JOIN profiles p ON p.user_id = u.id
       WHERE ${where} ORDER BY p.username ASC LIMIT $3 OFFSET $4`,
      [userId, pattern, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async report(client: DbClient, reporterId: string, targetId: string, reason: string): Promise<string> {
    const result = await client.query<{ id: string }>(
      `INSERT INTO reports (reporter_id, resource_type, resource_id, reason) VALUES ($1, 'profile', $2, $3) RETURNING id`,
      [reporterId, targetId, reason]
    );
    return result.rows[0]!.id;
  }
}
