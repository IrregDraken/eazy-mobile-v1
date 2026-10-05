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

  async delete(postId: string, authorId: string) {
    const deleted = await withTransaction(this.pool, client => this.repository.softDelete(client, postId, authorId));
    if (!deleted) throw new AppError('NOT_FOUND', 'Post not found');
    return { deleted: true, postId };
  }
}
