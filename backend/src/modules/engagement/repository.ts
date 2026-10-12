import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';

export interface CommentProjection {
  id: string;
  content: string;
  createdAt: string;
  parentId: string | null;
  likeCount: number;
  likedByViewer: boolean;
  author: { username: string; displayName: string; avatarUrl: string | null };
}

export interface SavedPostProjection {
  id: string;
  content: string;
  visibility: string;
  createdAt: string;
  author: { username: string; displayName: string; avatarUrl: string | null };
  likeCount: number;
  commentCount: number;
  saveCount: number;
  likedByViewer: boolean;
  savedByViewer: boolean;
}

export class EngagementRepository {
  constructor(private readonly pool: Pool) {}

  async postOwner(client: Pool | DbClient, postId: string): Promise<string | null> {
    const result = await client.query<{ author_id: string }>('SELECT author_id FROM posts WHERE id = $1 LIMIT 1', [postId]);
    return result.rows[0]?.author_id ?? null;
  }

  async assertAccessiblePost(client: Pool | DbClient, postId: string, viewerId: string): Promise<void> {
    const result = await client.query(
      `SELECT 1 FROM posts p
       WHERE p.id = $1 AND p.status = 'published'
         AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $2 AND b.blocked_id = p.author_id) OR (b.blocker_id = p.author_id AND b.blocked_id = $2))
         AND (p.author_id = $2 OR p.visibility = 'public' OR (p.visibility = 'followers' AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $2 AND f.followee_id = p.author_id)))
       LIMIT 1`,
      [postId, viewerId]
    );
    if (!result.rowCount) throw new Error('POST_INACCESSIBLE');
  }

  async like(client: DbClient, postId: string, userId: string): Promise<boolean> {
    const result = await client.query('INSERT INTO likes (user_id, post_id) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING user_id', [userId, postId]);
    return Boolean(result.rowCount);
  }

  async unlike(client: DbClient, postId: string, userId: string): Promise<boolean> {
    const result = await client.query('DELETE FROM likes WHERE user_id = $1 AND post_id = $2 RETURNING user_id', [userId, postId]);
    return Boolean(result.rowCount);
  }

  async createComment(client: DbClient, postId: string, authorId: string, content: string, parentId?: string): Promise<CommentProjection> {
    if (parentId) {
      const parent = await client.query('SELECT 1 FROM comments WHERE id=$1 AND post_id=$2 AND deleted_at IS NULL LIMIT 1', [parentId, postId]);
      if (!parent.rowCount) throw new Error('COMMENT_PARENT_INACCESSIBLE');
    }
    const result = await client.query<{ id: string; content: string; created_at: string; parent_id: string | null }>(
      'INSERT INTO comments (post_id, author_id, content, parent_id) VALUES ($1, $2, $3, $4) RETURNING id, content, created_at, parent_id',
      [postId, authorId, content, parentId ?? null]
    );
    const comment = result.rows[0]!;
    const author = await client.query<{ username: string; displayName: string; avatarUrl: string | null }>(
      `SELECT username, display_name AS "displayName", avatar_url AS "avatarUrl" FROM profiles WHERE user_id = $1 LIMIT 1`,
      [authorId]
    );
    return { id: comment.id, content: comment.content, createdAt: comment.created_at, parentId: comment.parent_id, likeCount: 0, likedByViewer: false, author: author.rows[0]! };
  }

  async listComments(postId: string, viewerId: string, page: number, limit: number): Promise<{ items: CommentProjection[]; total: number }> {
    const visibility = `c.post_id = $1 AND c.deleted_at IS NULL
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $2 AND b.blocked_id = c.author_id) OR (b.blocker_id = c.author_id AND b.blocked_id = $2))`;
    const count = await this.pool.query<{ count: string }>(`SELECT count(*)::text AS count FROM comments c WHERE ${visibility}`, [postId, viewerId]);
    const result = await this.pool.query<CommentProjection>(
      `SELECT c.id, c.content, c.created_at AS "createdAt", c.parent_id AS "parentId",
        (SELECT count(*)::int FROM comment_likes cl WHERE cl.comment_id=c.id) AS "likeCount",
        EXISTS(SELECT 1 FROM comment_likes mine WHERE mine.comment_id=c.id AND mine.user_id=$2) AS "likedByViewer",
        json_build_object('username', p.username, 'displayName', p.display_name, 'avatarUrl', p.avatar_url) AS author
       FROM comments c JOIN profiles p ON p.user_id = c.author_id
       WHERE ${visibility} ORDER BY c.created_at ASC, c.id ASC LIMIT $3 OFFSET $4`,
      [postId, viewerId, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async likeComment(client: DbClient, commentId: string, userId: string): Promise<boolean> {
    const accessible = await client.query(`SELECT 1 FROM comments c JOIN posts p ON p.id=c.post_id
      WHERE c.id=$1 AND c.deleted_at IS NULL AND p.status='published'
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$2 AND b.blocked_id=c.author_id) OR (b.blocker_id=c.author_id AND b.blocked_id=$2))
        AND (p.author_id=$2 OR p.visibility='public' OR (p.visibility='followers' AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id=$2 AND f.followee_id=p.author_id)))
      LIMIT 1`, [commentId, userId]);
    if (!accessible.rowCount) throw new Error('COMMENT_NOT_FOUND');
    const result = await client.query('INSERT INTO comment_likes (comment_id,user_id) VALUES ($1,$2) ON CONFLICT DO NOTHING RETURNING user_id', [commentId,userId]);
    return Boolean(result.rowCount);
  }

  async unlikeComment(client: DbClient, commentId: string, userId: string): Promise<boolean> {
    const result = await client.query('DELETE FROM comment_likes WHERE comment_id=$1 AND user_id=$2 RETURNING user_id', [commentId,userId]);
    return Boolean(result.rowCount);
  }

  async deleteComment(client: DbClient, commentId: string, authorId: string): Promise<boolean> {
    const result = await client.query('UPDATE comments SET deleted_at = now(), updated_at = now() WHERE id = $1 AND author_id = $2 AND deleted_at IS NULL RETURNING id', [commentId, authorId]);
    return Boolean(result.rowCount);
  }

  async save(client: DbClient, postId: string, userId: string): Promise<boolean> {
    const result = await client.query('INSERT INTO saves (user_id, post_id) VALUES ($1, $2) ON CONFLICT DO NOTHING RETURNING user_id', [userId, postId]);
    return Boolean(result.rowCount);
  }

  async unsave(client: DbClient, postId: string, userId: string): Promise<boolean> {
    const result = await client.query('DELETE FROM saves WHERE user_id = $1 AND post_id = $2 RETURNING user_id', [userId, postId]);
    return Boolean(result.rowCount);
  }

  async savedPosts(userId: string, page: number, limit: number): Promise<{ items: SavedPostProjection[]; total: number }> {
    const visibility = `s.user_id = $1 AND p.status = 'published'
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $1 AND b.blocked_id = p.author_id) OR (b.blocker_id = p.author_id AND b.blocked_id = $1))
      AND (p.author_id = $1 OR p.visibility = 'public' OR (p.visibility = 'followers' AND EXISTS (SELECT 1 FROM follows f WHERE f.follower_id = $1 AND f.followee_id = p.author_id)))`;
    const count = await this.pool.query<{ count: string }>(`SELECT count(*)::text AS count FROM saves s JOIN posts p ON p.id = s.post_id WHERE ${visibility}`, [userId]);
    const result = await this.pool.query<SavedPostProjection>(
      `SELECT p.id, p.content, p.visibility, p.created_at AS "createdAt",
        json_build_object('username', author.username, 'displayName', author.display_name, 'avatarUrl', author.avatar_url) AS author,
        (SELECT count(*)::int FROM likes l WHERE l.post_id = p.id) AS "likeCount",
        (SELECT count(*)::int FROM comments c WHERE c.post_id = p.id AND c.deleted_at IS NULL) AS "commentCount",
        (SELECT count(*)::int FROM saves s2 WHERE s2.post_id = p.id) AS "saveCount",
        EXISTS (SELECT 1 FROM likes l2 WHERE l2.post_id = p.id AND l2.user_id = $1) AS "likedByViewer",
        true AS "savedByViewer"
       FROM saves s JOIN posts p ON p.id = s.post_id JOIN profiles author ON author.user_id = p.author_id
       WHERE ${visibility} ORDER BY s.created_at DESC, p.id DESC LIMIT $2 OFFSET $3`,
      [userId, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }
}
