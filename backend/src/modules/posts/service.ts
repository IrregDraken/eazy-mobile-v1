import { z } from 'zod';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import { PostRepository, type PostProjection } from './repository.js';
import type { SupabaseStorageProvider } from '../../providers/supabase-storage.js';

const mediaSchema = z.object({
  storageKey: z.string().trim().min(1).max(1024),
  mediaType: z.enum(['image', 'video', 'audio']),
  position: z.number().int().min(0).max(99)
}).strict();

export const createPostSchema = z.object({
  content: z.string().trim().min(1).max(5000),
  visibility: z.enum(['public', 'followers', 'private']).default('public'),
  media: z.array(mediaSchema).max(10).default([])
}).strict();

export const postIdSchema = z.object({ id: z.string().uuid() });

export class PostService {
  constructor(private readonly pool: Pool, private readonly repository = new PostRepository(pool), private readonly storage?: SupabaseStorageProvider) {}

  async create(authorId: string, input: z.infer<typeof createPostSchema>) {
    const positions = input.media.map(item => item.position);
    if (new Set(positions).size !== positions.length) throw new AppError('VALIDATION_ERROR', 'Media positions must be unique');
    const post = await withTransaction(this.pool, client => this.repository.create(client, authorId, input.content, input.visibility, input.media));
    return this.attachMediaUrls(post);
  }

  async getById(postId: string, viewerId?: string) {
    const post = await this.repository.getById(this.pool, postId, viewerId);
    if (!post) throw new AppError('NOT_FOUND', 'Post not found');
    return this.attachMediaUrls(post);
  }

  async mine(userId: string, pagination: Pagination) {
    const result = await this.repository.mine(userId, pagination.page, pagination.limit);
    const items = await Promise.all(result.items.map(post => this.attachMediaUrls(post)));
    return { items, meta: paginationMeta(pagination, result.total) };
  }

  async byUsername(viewerId: string | undefined, username: string, pagination: Pagination, type: 'grid' | 'reels' | 'tagged' = 'grid') {
    const result = await this.repository.byUsername(viewerId, username, pagination.page, pagination.limit, type);
    const items = await Promise.all(result.items.map(post => this.attachMediaUrls(post)));
    return { items, meta: paginationMeta(pagination, result.total) };
  }

  async feed(viewerId: string, pagination: Pagination) {
    const result = await this.repository.feed(viewerId, pagination.page, pagination.limit, (pagination as any).mode ?? 'for_you');
    const items = await Promise.all(result.items.map(post => this.attachMediaUrls(post)));
    return { items, meta: paginationMeta(pagination, result.total) };
  }

  private async attachMediaUrls(post: PostProjection): Promise<PostProjection> {
    if (!this.storage || post.media.length === 0) return post;
    const media = await Promise.all(post.media.map(async item => {
      try {
        return { ...item, url: (await this.storage!.createSignedUrl(item.storageKey, 3600)).signedUrl };
      } catch {
        return { ...item, url: null };
      }
    }));
    return { ...post, media };
  }

  async pinPost(postId: string, authorId: string) {
    return withTransaction(this.pool, async client => {
      const post = await client.query('SELECT is_pinned FROM posts WHERE id=$1 AND author_id=$2 AND status=\'published\' FOR UPDATE', [postId, authorId]);
      if (!post.rowCount) throw new AppError('NOT_FOUND', 'Post not found');
      if (post.rows[0]!.is_pinned) return { pinned: true };
      const count = await client.query<{ count: string }>('SELECT count(*)::text AS count FROM posts WHERE author_id=$1 AND is_pinned=true AND status=\'published\'', [authorId]);
      if (Number(count.rows[0]?.count ?? 0) >= 3) throw new AppError('BAD_REQUEST', 'You can pin up to three posts on your profile');
      await client.query('UPDATE posts SET is_pinned=true, pinned_at=now(), updated_at=now() WHERE id=$1 AND author_id=$2', [postId, authorId]);
      return { pinned: true };
    });
  }

  async unpinPost(postId: string, authorId: string) {
    const result = await this.pool.query('UPDATE posts SET is_pinned=false, pinned_at=NULL, updated_at=now() WHERE id=$1 AND author_id=$2 AND is_pinned=true RETURNING id', [postId, authorId]);
    if (!result.rowCount) throw new AppError('NOT_FOUND', 'Pinned post not found');
    return { pinned: false };
  }

  async tagPeople(postId: string, authorId: string, usernames: string[]) {
    const normalized = [...new Set(usernames.map(name => name.trim().toLowerCase()))];
    return withTransaction(this.pool, async client => {
      const post = await client.query('SELECT 1 FROM posts WHERE id=$1 AND author_id=$2 AND status=\'published\' LIMIT 1', [postId, authorId]);
      if (!post.rowCount) throw new AppError('NOT_FOUND', 'Post not found');
      const people = await client.query<{ user_id: string; username: string }>('SELECT user_id, username FROM profiles WHERE username=ANY($1::text[])', [normalized]);
      if (people.rows.length !== normalized.length) throw new AppError('VALIDATION_ERROR', 'One or more usernames could not be found');
      for (const person of people.rows) {
        if (person.user_id === authorId) continue;
        await client.query('INSERT INTO post_tags (post_id,user_id,tagged_by) VALUES ($1,$2,$3) ON CONFLICT DO NOTHING', [postId, person.user_id, authorId]);
      }
      return { tagged: people.rows.filter(person => person.user_id !== authorId).map(person => person.username) };
    });
  }

  async untagPerson(postId: string, authorId: string, username: string) {
    const result = await this.pool.query(`DELETE FROM post_tags pt USING posts p, profiles target
      WHERE pt.post_id=$1 AND p.id=pt.post_id AND p.author_id=$2 AND target.username=$3 AND pt.user_id=target.user_id
      RETURNING pt.user_id`, [postId, authorId, username.toLowerCase()]);
    if (!result.rowCount) throw new AppError('NOT_FOUND', 'Post tag not found');
    return { removed: true };
  }

  async delete(postId: string, authorId: string) {
    const deleted = await withTransaction(this.pool, client => this.repository.softDelete(client, postId, authorId));
    if (!deleted) throw new AppError('NOT_FOUND', 'Post not found');
    return { deleted: true, postId };
  }
}
