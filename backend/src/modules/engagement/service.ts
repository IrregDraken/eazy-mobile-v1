import { z } from 'zod';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import type { DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import { EngagementRepository } from './repository.js';
import type { NotificationService } from '../notifications/service.js';
import { notifyComment, notifyLike } from '../notifications/producers/social.js';

export const commentSchema = z.object({ content: z.string().trim().min(1).max(2000) }).strict();
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

  async createComment(postId: string, userId: string, content: string) {
    const result = await withTransaction(this.pool, async client => {
      await this.assertAccessible(client, postId, userId);
      const comment = await this.repository.createComment(client, postId, userId, content);
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
