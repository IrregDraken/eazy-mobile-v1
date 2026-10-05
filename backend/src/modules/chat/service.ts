import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import type { Pool } from 'pg';
import { SocialRepository } from '../social/repository.js';
import { ChatRepository } from './repository.js';
import type { ChatBlockChecker, ChatRepositoryContract } from './types.js';
import type { RealtimePublisher } from '../realtime/service.js';
import { eventForMessage, eventForReaction, eventForRead } from '../realtime/events.js';
import type { NotificationService } from '../notifications/service.js';

const usernamePattern = /^[a-z0-9_]{3,32}$/;
const validUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export class ChatService {
  constructor(
    private readonly pool: Pool,
    private readonly repository: ChatRepositoryContract = new ChatRepository(pool),
    private readonly blocks: ChatBlockChecker = new SocialRepository(pool),
    private readonly realtime?: RealtimePublisher,
    private readonly notifications?: NotificationService
  ) {}

  async createConversation(currentUserId: string, rawUsername: string) {
    const username = normalizeUsername(rawUsername);
    const creation = await withTransaction(this.pool, async client => {
      const target = await this.repository.findTargetByUsername(client, username);
      if (!target) throw new AppError('NOT_FOUND', 'User not found');
      if (target.id === currentUserId) throw new AppError('BAD_REQUEST', 'You cannot start a conversation with yourself');
      const sortedParticipantIds = [currentUserId, target.id].sort();
      const firstUserId = sortedParticipantIds[0]!;
      const secondUserId = sortedParticipantIds[1]!;
      await this.repository.lockDirectConversation(client, firstUserId, secondUserId);
      if (await this.blocks.isBlocked(client, currentUserId, target.id)) throw new AppError('FORBIDDEN', 'This conversation is unavailable');
      let conversationId = await this.repository.findDirectConversation(client, firstUserId, secondUserId);
      const created = !conversationId;
      if (!conversationId) conversationId = await this.repository.createDirectConversation(client, currentUserId, target.id);
      return { conversationId, created };
    });
    const conversation = await this.repository.getConversation(currentUserId, creation.conversationId);
    if (!conversation) throw new AppError('INTERNAL_ERROR', 'Created conversation could not be read');
    return { conversation, created: creation.created };
  }

  async listConversations(currentUserId: string, pagination: Pagination) {
    const result = await this.repository.listConversations(currentUserId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  async getConversation(currentUserId: string, conversationId: string) {
    const conversation = await this.repository.getConversation(currentUserId, conversationId);
    if (!conversation) throw new AppError('NOT_FOUND', 'Conversation not found');
    return { conversation };
  }

  async listMessages(currentUserId: string, conversationId: string, pagination: Pagination) {
    const result = await this.repository.listMessages(currentUserId, conversationId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }

  async sendMessage(currentUserId: string, conversationId: string, input: { body: string; replyToMessageId?: string }) {
    const body = normalizeBody(input.body);
    const created = await withTransaction(this.pool, async client => {
      if (!await this.repository.isActiveMember(client, conversationId, currentUserId)) throw new AppError('NOT_FOUND', 'Conversation not found');
      await this.assertNotBlocked(client, currentUserId, conversationId);
      if (input.replyToMessageId && !await this.repository.replyBelongsToConversation(client, input.replyToMessageId, conversationId, currentUserId)) {
        throw new AppError('BAD_REQUEST', 'Reply target is not in this conversation');
      }
      const messageId = await this.repository.createMessage(client, conversationId, currentUserId, body, input.replyToMessageId);
      if (!messageId) throw new AppError('NOT_FOUND', 'Conversation not found');
      const recipients = this.notifications ? await this.repository.getOtherParticipantIds(client, conversationId, currentUserId) : [];
      return { messageId, recipients };
    });
    const message = await this.repository.getMessageForMember(this.pool, created.messageId, currentUserId);
    if (!message) throw new AppError('INTERNAL_ERROR', 'Created message could not be read');
    await this.publish(() => this.realtime?.messageCreated(conversationId, eventForMessage(message)));
    if (this.notifications) {
      for (const recipientUserId of created.recipients) {
        try {
          await this.notifications.create({
            recipientUserId,
            actorUserId: currentUserId,
            type: 'message',
            entityType: 'conversation',
            entityId: conversationId,
            title: 'New message',
            body: body.length > 120 ? `${body.slice(0, 117)}…` : body,
            deepLink: `eazy://chat/${conversationId}`
          });
        } catch { /* message persistence is independent of push delivery */ }
      }
    }
    return { message };
  }

  async deleteMessage(currentUserId: string, messageId: string) {
    return withTransaction(this.pool, async client => {
      const existing = await this.repository.getMessageForMember(client, messageId, currentUserId);
      if (!existing) throw new AppError('NOT_FOUND', 'Message not found');
      const owned = await this.repository.getMessageAsSender(client, messageId, currentUserId);
      if (!owned) throw new AppError('FORBIDDEN', 'You can only delete your own messages');
      const deleted = await this.repository.softDeleteMessage(client, messageId, currentUserId);
      return { deleted: deleted || existing.status === 'deleted' };
    });
  }

  async editMessage(currentUserId: string, messageId: string, rawBody: string) {
    const body = normalizeBody(rawBody);
    return withTransaction(this.pool, async client => {
      const existing = await this.repository.getMessageForMember(client, messageId, currentUserId);
      if (!existing) throw new AppError('NOT_FOUND', 'Message not found');
      const owned = await this.repository.getMessageAsSender(client, messageId, currentUserId);
      if (!owned) throw new AppError('FORBIDDEN', 'You can only edit your own messages');
      if (existing.status === 'deleted') throw new AppError('CONFLICT', 'Deleted messages cannot be edited');
      await this.repository.editMessage(client, messageId, currentUserId, body);
      const updated = await this.repository.getMessageForMember(client, messageId, currentUserId);
      if (!updated) throw new AppError('INTERNAL_ERROR', 'Updated message could not be read');
      return { message: updated };
    });
  }

  async reportMessage(currentUserId: string, messageId: string, reason: string) {
    const reportId = await withTransaction(this.pool, async client => {
      const created = await this.repository.createMessageReport(client, messageId, currentUserId, reason);
      if (!created) throw new AppError('NOT_FOUND', 'Message not found');
      return created;
    });
    return { submitted: true, reportId };
  }

  async addReaction(currentUserId: string, messageId: string, reaction: string) {
    const result = await withTransaction(this.pool, async client => {
      const message = await this.repository.getMessageForMember(client, messageId, currentUserId);
      if (!message || message.status === 'deleted') throw new AppError('NOT_FOUND', 'Message not found');
      return { added: await this.repository.addReaction(client, messageId, currentUserId, reaction), conversationId: message.conversationId };
    });
    if (result.added) await this.publish(() => this.realtime?.reactionChanged(result.conversationId, eventForReaction('message.reaction.created', result.conversationId, messageId, reaction)));
    return { added: result.added };
  }

  async removeReaction(currentUserId: string, messageId: string, reaction: string) {
    const result = await withTransaction(this.pool, async client => {
      const message = await this.repository.getMessageForMember(client, messageId, currentUserId);
      if (!message) throw new AppError('NOT_FOUND', 'Message not found');
      return { removed: await this.repository.removeReaction(client, messageId, currentUserId, reaction), conversationId: message.conversationId };
    });
    if (result.removed) await this.publish(() => this.realtime?.reactionChanged(result.conversationId, eventForReaction('message.reaction.deleted', result.conversationId, messageId, reaction)));
    return { removed: result.removed };
  }

  async markRead(currentUserId: string, conversationId: string, requestedMessageId?: string) {
    const read = await withTransaction(this.pool, async client => {
      if (!await this.repository.isActiveMember(client, conversationId, currentUserId)) throw new AppError('NOT_FOUND', 'Conversation not found');
      const messageId = requestedMessageId ?? await this.repository.getLatestMessageId(client, conversationId, currentUserId);
      const state = await this.repository.markRead(client, conversationId, currentUserId, messageId);
      if (!state) throw new AppError('BAD_REQUEST', 'Read marker must reference a message in this conversation');
      return state;
    });
    await this.publish(async () => {
      if (!this.realtime) return;
      const reader = await this.repository.getActiveParticipantProfile(this.pool, conversationId, currentUserId);
      if (!reader) return;
      await this.realtime.readStateChanged(conversationId, eventForRead(read.conversationId, read.lastReadMessageId, read.readAt, reader));
    });
    return { read };
  }

  private async publish(publish: () => Promise<unknown> | undefined): Promise<void> {
    try { await publish(); } catch { /* realtime is best-effort and cannot fail a persisted REST operation */ }
  }

  private async assertNotBlocked(client: import('pg').PoolClient, currentUserId: string, conversationId: string) {
    const participants = await this.repository.getOtherParticipantIds(client, conversationId, currentUserId);
    for (const participantId of participants) {
      const sortedIds = [currentUserId, participantId].sort();
      await this.repository.lockDirectConversation(client, sortedIds[0]!, sortedIds[1]!);
      if (await this.blocks.isBlocked(client, currentUserId, participantId)) throw new AppError('FORBIDDEN', 'This conversation is unavailable');
    }
  }
}

function normalizeUsername(rawUsername: string): string {
  const username = rawUsername.trim().toLowerCase();
  if (!usernamePattern.test(username)) throw new AppError('VALIDATION_ERROR', 'Invalid username');
  return username;
}

function normalizeBody(rawBody: string): string {
  const body = rawBody.trim();
  if (!body || Array.from(body).length > 10_000) throw new AppError('VALIDATION_ERROR', 'Message body must contain 1 to 10000 characters');
  return body;
}

export function validMessageCursor(value: string): boolean { return validUuid.test(value); }
