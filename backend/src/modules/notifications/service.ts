import { z } from 'zod';
import type { Pool } from 'pg';
import { withTransaction, type DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import { NotificationRepository, type NotificationInput } from './repository.js';
import type { DeviceRegistration } from './schemas.js';
import type { RealtimePublisher } from '../realtime/service.js';
import { eventForNotification } from '../realtime/events.js';
import type { NotificationProvider } from '../../providers/interfaces.js';

export class NotificationService {
  constructor(private readonly pool: Pool, private readonly repository = new NotificationRepository(pool), private readonly realtime?: RealtimePublisher, private readonly push?: NotificationProvider) {}

  async create(input: NotificationInput): Promise<string | null> {
    if (input.actorUserId && input.actorUserId === input.recipientUserId) return null;
    const id = await withTransaction(this.pool, db => this.repository.create(db, input));
    if (id) {
      await this.publishCreated(input.recipientUserId, id);
      if (this.push && input.title && input.body) {
        try { await this.push.notify({ userId: input.recipientUserId, title: input.title, body: input.body }); } catch { /* REST notification remains truthful when delivery fails. */ }
      }
    }
    return id;
  }

  async publishCreated(userId: string, id: string): Promise<void> {
    if (!this.realtime) return;
    try {
      const notification = await this.repository.get(userId, id);
      if (notification) await this.realtime.publishToUser(userId, eventForNotification(notification));
    } catch { /* persisted notifications remain available through REST when realtime is unavailable */ }
  }

  async createInTransaction(db: DbClient, input: NotificationInput) {
    return this.repository.create(db, input);
  }

  async list(userId: string, pagination: Pagination) {
    const result = await this.repository.list(userId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  async get(userId: string, id: string) {
    const notification = await this.repository.get(userId, id);
    if (!notification) throw new AppError('NOT_FOUND', 'Notification not found');
    return { notification };
  }

  async markRead(userId: string, id: string) {
    const changed = await this.repository.markRead(userId, id);
    if (!changed) throw new AppError('NOT_FOUND', 'Notification not found');
    return { read: true, id };
  }

  async markAllRead(userId: string) { return { updated: await this.repository.markAllRead(userId) }; }
  async unreadCount(userId: string) { return { unreadCount: await this.repository.unreadCount(userId) }; }

  async registerDevice(userId: string, input: DeviceRegistration) {
    try { return { deviceId: await this.repository.registerDevice(userId, input.token, input.platform), pushDelivery: this.push ? 'available' as const : 'unavailable' as const }; }
    catch (error) { if (error instanceof Error && error.message === 'DEVICE_OWNERSHIP') throw new AppError('FORBIDDEN', 'Device token belongs to another user'); throw error; }
  }

  async deleteDevice(userId: string, id: string) {
    const deleted = await this.repository.deleteDevice(userId, id);
    if (!deleted) throw new AppError('NOT_FOUND', 'Device not found');
    return { deleted: true, id };
  }
}

export const notificationTypeSchema = z.enum(['follow', 'like', 'comment', 'message', 'order', 'payment', 'system']);
