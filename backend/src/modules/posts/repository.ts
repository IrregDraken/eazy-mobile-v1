import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';

export interface PostMediaInput { storageKey: string; mediaType: string; position: number; }
export interface PostProjection {
  id: string;
  content: string;
  visibility: 'public' | 'followers' | 'private';
  createdAt: string;
  author: { username: string; displayName: string; avatarUrl: string | null };
  media: { storageKey: string; mediaType: string; position: number }[];
  likeCount: number;
  commentCount: number;
  saveCount: number;
  likedByViewer: boolean;
  savedByViewer: boolean;
}

const projection = `p.id, p.content, p.visibility, p.created_at AS "createdAt",
  json_build_object('username', author.username, 'displayName', author.display_name, 'avatarUrl', author.avatar_url) AS author,
  COALESCE((SELECT json_agg(json_build_object('storageKey', pm.storage_key, 'mediaType', pm.media_type, 'position', pm.position) ORDER BY pm.position) FROM post_media pm WHERE pm.post_id = p.id), '[]'::json) AS media,
  (SELECT count(*)::int FROM likes l WHERE l.post_id = p.id) AS "likeCount",
  (SELECT count(*)::int FROM comments c WHERE c.post_id = p.id AND c.deleted_at IS NULL) AS "commentCount",
  (SELECT count(*)::int FROM saves s WHERE s.post_id = p.id) AS "saveCount",
  EXISTS (SELECT 1 FROM likes viewer_like WHERE viewer_like.post_id = p.id AND viewer_like.user_id = $1) AS "likedByViewer",
  EXISTS (SELECT 1 FROM saves viewer_save WHERE viewer_save.post_id = p.id AND viewer_save.user_id = $1) AS "savedByViewer"`;

export class PostRepository {
  constructor(private readonly pool: Pool) {}

  async create(client: DbClient, authorId: string, content: string, visibility: string, media: PostMediaInput[]): Promise<PostProjection> {
    const created = await client.query<{ id: string }>('INSERT INTO posts (author_id, content, visibility, status) VALUES ($1, $2, $3, \'published\') RETURNING id', [authorId, content, visibility]);
    const postId = created.rows[0]!.id;
    for (const item of media) await client.query('INSERT INTO post_media (post_id, storage_key, media_type, position) VALUES ($1, $2, $3, $4)', [postId, item.storageKey, item.mediaType, item.position]);
    const result = await this.getById(client, postId, authorId);
    if (!result) throw new Error('Created post could not be read');
    return result;
  }

  async getById(client: Pool | DbClient, postId: string, viewerId?: string): Promise<PostProjection | null> {
    const result = await client.query<PostProjection>(
      `SELECT ${projection}
       FROM posts p JOIN profiles author ON author.user_id = p.author_id
       WHERE p.id = $2 AND p.status = 'published'
         AND ($1::uuid IS NULL OR NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = p.author_id) OR (b.blocker_id = p.author_id AND b.blocked_id = $1)))
         AND ($1::uuid IS NOT NULL AND p.author_id = $1 OR p.visibility = 'public' OR ($1::uuid IS NOT NULL AND p.visibility = 'followers' AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $1 AND f.followee_id = p.author_id)))`,
      [viewerId ?? null, postId]
    );
    return result.rows[0] ?? null;
  }

  async feed(viewerId: string, page: number, limit: number, mode: 'for_you' | 'following' | 'trending' = 'for_you'): Promise<{ items: PostProjection[]; total: number }> {
    const args = [viewerId, limit, (page - 1) * limit];
    const whereParts = [
      `p.status = 'published'`,
      `NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = p.author_id) OR (b.blocker_id = p.author_id AND b.blocked_id = $1))`
    ];

    if (mode === 'trending') {
      whereParts.push(`p.visibility = 'public'`);
      whereParts.push(`p.created_at >= now() - interval '7 days'`);
    } else if (mode === 'following') {
      whereParts.push(`EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $1 AND f.followee_id = p.author_id)`);
      whereParts.push(`(p.visibility = 'public' OR p.visibility = 'followers')`);
    } else {
      whereParts.push(`(p.author_id = $1 OR EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $1 AND f.followee_id = p.author_id))`);
      whereParts.push(`(p.author_id = $1 OR p.visibility = 'public' OR (p.visibility = 'followers' AND EXISTS (SELECT 1 FROM follows f2 WHERE f2.follower_id = $1 AND f2.followee_id = p.author_id)))`);
    }

    const where = whereParts.join(' AND ');
    const count = await this.pool.query<{ count: string }>(`SELECT count(*)::text AS count FROM posts p WHERE ${where}`, [viewerId]);
    const order = mode === 'trending'
      ? `(SELECT count(*) FROM likes l WHERE l.post_id = p.id) DESC,
         (SELECT count(*) FROM comments c WHERE c.post_id = p.id AND c.deleted_at IS NULL) DESC,
         p.created_at DESC, p.id DESC`
      : 'p.created_at DESC, p.id DESC';
    const result = await this.pool.query<PostProjection>(
      `SELECT ${projection}
       FROM posts p JOIN profiles author ON author.user_id = p.author_id
       WHERE ${where}
       ORDER BY ${order}
       LIMIT $2 OFFSET $3`,
      args
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }
  async mine(userId: string, page: number, limit: number): Promise<{ items: PostProjection[]; total: number }> {
    const count = await this.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM posts WHERE author_id = $1 AND status = 'published'`,
      [userId]
    );
    const result = await this.pool.query<PostProjection>(
      `SELECT ${projection}
       FROM posts p JOIN profiles author ON author.user_id = p.author_id
       WHERE p.author_id = $1 AND p.status = 'published'
       ORDER BY p.created_at DESC, p.id DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async softDelete(client: DbClient, postId: string, authorId: string): Promise<boolean> {
    const result = await client.query("UPDATE posts SET status = 'deleted', updated_at = now() WHERE id = $1 AND author_id = $2 AND status <> 'deleted' RETURNING id", [postId, authorId]);
    return Boolean(result.rowCount);
  }
}
