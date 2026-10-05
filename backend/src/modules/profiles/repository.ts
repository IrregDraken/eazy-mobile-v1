import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';

export interface ProfileRecord {
  user_id: string;
  username: string;
  display_name: string;
  first_name: string | null;
  middle_name: string | null;
  last_name: string | null;
  date_of_birth: string | null;
  bio: string | null;
  avatar_url: string | null;
  onboarding_status: 'profile_incomplete' | 'onboarding_complete';
}

export interface PublicProfileRecord {
  user_id: string;
  username: string;
  display_name: string;
  first_name: string | null;
  last_name: string | null;
  bio: string | null;
  avatar_url: string | null;
  onboarding_status: 'profile_incomplete' | 'onboarding_complete';
}

export interface ProfileStats {
  posts: number;
  followers: number;
  following: number;
}


const profileColumns = 'user_id, username, display_name, first_name, middle_name, last_name, date_of_birth, bio, avatar_url, onboarding_status';

export class ProfileRepository {
  constructor(private readonly pool: Pool) {}

  async getByUserId(userId: string, client: Pool | DbClient = this.pool): Promise<ProfileRecord | null> {
    const result = await client.query<ProfileRecord>(`SELECT ${profileColumns} FROM profiles WHERE user_id = $1 LIMIT 1`, [userId]);
    return result.rows[0] ?? null;
  }

  async getPublicByUsername(username: string, viewerId?: string): Promise<PublicProfileRecord | null> {
    const result = await this.pool.query<PublicProfileRecord>(
      `SELECT p.user_id, username, display_name, first_name, middle_name, last_name, bio, avatar_url, onboarding_status
       FROM profiles p JOIN users u ON u.id = p.user_id AND u.status = 'active'
       WHERE p.username = $1
         AND ($2::uuid IS NULL OR NOT EXISTS (
           SELECT 1 FROM blocks b WHERE (b.blocker_id = $2 AND b.blocked_id = p.user_id)
             OR (b.blocker_id = p.user_id AND b.blocked_id = $2)
         ))
       LIMIT 1`,
      [username.toLowerCase(), viewerId ?? null]
    );
    return result.rows[0] ?? null;
  }

  async getStats(userId: string): Promise<ProfileStats> {
    const result = await this.pool.query<ProfileStats>(
      `SELECT
         (SELECT count(*)::int FROM posts WHERE author_id = $1 AND status = 'published') AS posts,
         (SELECT count(*)::int FROM follows WHERE followee_id = $1) AS followers,
         (SELECT count(*)::int FROM follows WHERE follower_id = $1) AS following`,
      [userId]
    );
    return result.rows[0] ?? { posts: 0, followers: 0, following: 0 };
  }

  async usernameAvailable(username: string, excludeUserId?: string): Promise<boolean> {
    const result = await this.pool.query<{ exists: boolean }>(
      'SELECT EXISTS (SELECT 1 FROM profiles WHERE username = $1 AND ($2::uuid IS NULL OR user_id <> $2::uuid)) AS exists',
      [username.toLowerCase(), excludeUserId ?? null]
    );
    return !result.rows[0]?.exists;
  }

  async updateCurrent(client: DbClient, userId: string, fields: Record<string, unknown>): Promise<ProfileRecord | null> {
    const allowed = ['username', 'display_name', 'first_name', 'middle_name', 'last_name', 'date_of_birth', 'bio', 'avatar_url'] as const;
    const entries = Object.entries(fields).filter(([key, value]) => allowed.includes(key as typeof allowed[number]) && value !== undefined);
    if (entries.length === 0) return this.getByUserId(userId, client);
    const set = entries.map(([key], index) => `${key} = $${index + 2}`).join(', ');
    const values = entries.map(([, value]) => value);
    try {
      const result = await client.query<ProfileRecord>(
        `UPDATE profiles SET ${set}, updated_at = now() WHERE user_id = $1 RETURNING ${profileColumns}`,
        [userId, ...values]
      );
      return result.rows[0] ?? null;
    } catch (error: unknown) {
      if ((error as { code?: string }).code === '23505') throw Object.assign(new Error('Username is already taken'), { code: 'PROFILE_USERNAME_CONFLICT' });
      throw error;
    }
  }

  async completeOnboarding(client: DbClient, userId: string): Promise<ProfileRecord | null> {
    const result = await client.query<ProfileRecord>(
      `UPDATE profiles SET onboarding_status = 'onboarding_complete', updated_at = now()
       WHERE user_id = $1 AND username IS NOT NULL AND first_name IS NOT NULL AND date_of_birth IS NOT NULL
       RETURNING ${profileColumns}`,
      [userId]
    );
    return result.rows[0] ?? null;
  }
}
