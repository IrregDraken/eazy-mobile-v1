import { z } from 'zod';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import type { Pool } from 'pg';
import { SocialRepository } from './repository.js';
import type { NotificationService } from '../notifications/service.js';
import { notifyFollow } from '../notifications/producers/social.js';

const usernamePattern = /^[a-z0-9_]{3,32}$/;
export const socialUsernameSchema = z.string().trim().toLowerCase().regex(usernamePattern, 'Invalid username');
export const searchQuerySchema = z.object({ q: z.string().trim().toLowerCase().min(2).max(80), page: z.coerce.number().int().min(1).default(1), limit: z.coerce.number().int().min(1).max(50).default(20) });
export const socialPaginationSchema = z.object({ page: z.coerce.number().int().min(1).default(1), limit: z.coerce.number().int().min(1).max(50).default(20) });
export const reportSchema = z.object({ reason: z.string().trim().min(3).max(1000) }).strict();

export class SocialService {
  constructor(private readonly pool: Pool, private readonly repository = new SocialRepository(pool), private readonly notifications?: NotificationService) {}

  async follow(currentUserId: string, rawUsername: string) {
    const result = await withTransaction(this.pool, async client => {
      const target = await this.target(client, rawUsername);
      this.assertNotSelf(currentUserId, target.id);
      if (await this.repository.isBlocked(client, currentUserId, target.id)) throw new AppError('FORBIDDEN', 'This relationship is blocked');
      const created = await this.repository.follow(client, currentUserId, target.id);
      const notificationId = created && this.notifications ? await notifyFollow(client, this.notifications, currentUserId, target.id) : null;
      return { response: { following: true, username: target.username }, notificationId, recipientId: target.id };
    });
    if (result.notificationId && this.notifications) await this.notifications.publishCreated(result.recipientId, result.notificationId);
    return result.response;
  }

  async unfollow(currentUserId: string, rawUsername: string) {
    return withTransaction(this.pool, async client => {
      const target = await this.target(client, rawUsername);
      this.assertNotSelf(currentUserId, target.id);
      const removed = await this.repository.unfollow(client, currentUserId, target.id);
      return { following: false, removed, username: target.username };
    });
  }

  async block(currentUserId: string, rawUsername: string) {
    return withTransaction(this.pool, async client => {
      const target = await this.target(client, rawUsername);
      this.assertNotSelf(currentUserId, target.id);
      const created = await this.repository.block(client, currentUserId, target.id);
      return { blocked: true, created, username: target.username };
    });
  }

  async unblock(currentUserId: string, rawUsername: string) {
    return withTransaction(this.pool, async client => {
      const target = await this.target(client, rawUsername);
      this.assertNotSelf(currentUserId, target.id);
      const removed = await this.repository.unblock(client, currentUserId, target.id);
      return { blocked: false, removed, username: target.username };
    });
  }

  async blockUser(currentUserId: string, targetUserId: string) {
    return withTransaction(this.pool, async client => {
      const target = await this.repository.targetById(client, targetUserId);
      if (!target) throw new AppError('NOT_FOUND', 'User not found');
      this.assertNotSelf(currentUserId, target.id);
      const created = await this.repository.block(client, currentUserId, target.id);
      return { blocked: true, created, user: { username: target.username } };
    });
  }

  async unblockUser(currentUserId: string, targetUserId: string) {
    return withTransaction(this.pool, async client => {
      const target = await this.repository.targetById(client, targetUserId);
      if (!target) throw new AppError('NOT_FOUND', 'User not found');
      this.assertNotSelf(currentUserId, target.id);
      const removed = await this.repository.unblock(client, currentUserId, target.id);
      return { blocked: false, removed, user: { username: target.username } };
    });
  }

  async relationship(currentUserId: string, rawUsername: string) {
    const target = await this.repository.targetByUsername(this.pool, normalizeUsername(rawUsername));
    if (!target) throw new AppError('NOT_FOUND', 'User not found');
    if (target.id === currentUserId) return { following: false, followedBy: false, blocked: false, blockedBy: false, self: true };
    const state = await this.repository.relationship(this.pool, currentUserId, target.id);
    return { following: state.following, followedBy: state.followed_by, blocked: state.blocked, blockedBy: state.blocked_by, self: false };
  }

  async list(currentUserId: string | undefined, direction: 'followers' | 'following', rawUsername: string, pagination: Pagination) {
    const username = normalizeUsername(rawUsername);
    const result = await this.repository.list(this.pool, direction, username, pagination.page, pagination.limit, currentUserId);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  async listBlocks(currentUserId: string, pagination: Pagination) {
    const result = await this.repository.blocks(this.pool, currentUserId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  async search(currentUserId: string, input: z.infer<typeof searchQuerySchema>) {
    const result = await this.repository.search(this.pool, currentUserId, input.q, input.page, input.limit);
    return { items: result.items, meta: paginationMeta(input, result.total) };
  }

  async report(currentUserId: string, rawUsername: string, reason: string) {
    return withTransaction(this.pool, async client => {
      const target = await this.target(client, rawUsername);
      this.assertNotSelf(currentUserId, target.id);
      const reportId = await this.repository.report(client, currentUserId, target.id, reason);
      return { submitted: true, reportId };
    });
  }

  private async target(client: Parameters<typeof this.repository.targetByUsername>[0], rawUsername: string) {
    const username = normalizeUsername(rawUsername);
    const target = await this.repository.targetByUsername(client, username);
    if (!target) throw new AppError('NOT_FOUND', 'User not found');
    return target;
  }

  private assertNotSelf(currentUserId: string, targetId: string) {
    if (currentUserId === targetId) throw new AppError('BAD_REQUEST', 'You cannot perform this action on yourself');
  }
}

function normalizeUsername(value: string) {
  const username = value.trim().toLowerCase();
  if (!usernamePattern.test(username)) throw new AppError('VALIDATION_ERROR', 'Invalid username');
  return username;
}
