import { z } from 'zod';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import type { DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import { EngagementRepository } from './repository.js';
import type { NotificationService } from '../notifications/service.js';
import { notifyComment, notifyLike } from '../notifications/producers/social.js';

export const commentSchema = z.object({ content: z.string().trim().min(1).max(2000), parentId: z.string().uuid().optional() }).strict();
export const reportPostSchema = z.object({ reason: z.string().trim().min(3).max(1000) }).strict();
export const postIdParamSchema = z.object({ postId: z.string().uuid() });
export const commentIdParamSchema = z.object({ commentId: z.string().uuid() });

export class EngagementService {
  constructor(private readonly pool: Pool, private readonly repository = new EngagementRepository(pool), private readonly notifications?: NotificationService) {}

  async like(postId: string, userId: string) {
    const result = await withTransaction(this.pool, async client => {
      await this.assertAccessible(client, postId, userId);
      const created = await this.repository.like(client, postId, userId);
      let notificationId: string | null = null;
      let recipientId: string | null = null;
      if (created && this.notifications) {
        const ownerId = await this.repository.postOwner(client, postId);
        if (ownerId) {
          notificationId = await notifyLike(client, this.notifications, userId, ownerId, postId);
          recipientId = ownerId;
        }
      }
      return { response: { liked: true, created }, notificationId, recipientId };
    });
    if (result.notificationId && result.recipientId && this.notifications) await this.notifications.publishCreated(result.recipientId, result.notificationId);
    return result.response;
  }

  async unlike(postId: string, userId: string) {
    return withTransaction(this.pool, async client => {
      await this.assertAccessible(client, postId, userId);
      const removed = await this.repository.unlike(client, postId, userId);
      return { liked: false, removed };
    });
  }

  async createComment(postId: string, userId: string, content: string, parentId?: string) {
    const result = await withTransaction(this.pool, async client => {
      await this.assertAccessible(client, postId, userId);
      let comment;
      try { comment = await this.repository.createComment(client, postId, userId, content, parentId); }
      catch (error) { if (error instanceof Error && error.message === 'COMMENT_PARENT_INACCESSIBLE') throw new AppError('NOT_FOUND', 'Reply target not found'); throw error; }
      let notificationId: string | null = null;
      let recipientId: string | null = null;
      if (this.notifications) {
        const ownerId = await this.repository.postOwner(client, postId);
        if (ownerId) {
          notificationId = await notifyComment(client, this.notifications, userId, ownerId, postId);
          recipientId = ownerId;
        }
      }
      return { response: { comment }, notificationId, recipientId };
    });
    if (result.notificationId && result.recipientId && this.notifications) await this.notifications.publishCreated(result.recipientId, result.notificationId);
    return result.response;
  }

  async listComments(postId: string, userId: string, pagination: Pagination) {
    await this.assertAccessible(this.pool, postId, userId);
    const result = await this.repository.listComments(postId, userId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  async likeComment(commentId: string, userId: string) {
    try {
      const created = await withTransaction(this.pool, client => this.repository.likeComment(client, commentId, userId));
      return { liked: true, created };
    } catch (error) {
      if (error instanceof Error && error.message === 'COMMENT_NOT_FOUND') throw new AppError('NOT_FOUND', 'Comment not found');
      throw error;
    }
  }

  async unlikeComment(commentId: string, userId: string) {
    return { liked: false, removed: await withTransaction(this.pool, client => this.repository.unlikeComment(client, commentId, userId)) };
  }

  async reportPost(postId: string, userId: string, reason: string) {
    await this.assertAccessible(this.pool, postId, userId);
    const result = await this.pool.query<{ id: string }>(
      "INSERT INTO reports (reporter_id, resource_type, resource_id, reason) VALUES ($1,'post',$2,$3) RETURNING id",
      [userId, postId, reason]
    );
    return { submitted: true, reportId: result.rows[0]!.id };
  }

  async deleteComment(commentId: string, userId: string) {
    const deleted = await withTransaction(this.pool, client => this.repository.deleteComment(client, commentId, userId));
    if (!deleted) throw new AppError('NOT_FOUND', 'Comment not found');
    return { deleted: true, commentId };
  }

  async save(postId: string, userId: string) {
    return withTransaction(this.pool, async client => {
      await this.assertAccessible(client, postId, userId);
      const created = await this.repository.save(client, postId, userId);
      return { saved: true, created };
    });
  }

  async unsave(postId: string, userId: string) {
    return withTransaction(this.pool, async client => {
      await this.assertAccessible(client, postId, userId);
      const removed = await this.repository.unsave(client, postId, userId);
      return { saved: false, removed };
    });
  }

  async savedPosts(userId: string, pagination: Pagination) {
    const result = await this.repository.savedPosts(userId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  private async assertAccessible(client: Pool | DbClient, postId: string, userId: string): Promise<void> {
    try {
      await this.repository.assertAccessiblePost(client, postId, userId);
    } catch (error: unknown) {
      if (error instanceof Error && error.message === 'POST_INACCESSIBLE') throw new AppError('NOT_FOUND', 'Post not found');
      throw error;
    }
  }
}
