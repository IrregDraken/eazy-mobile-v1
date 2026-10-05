import type { Pool } from 'pg';
import type { ChatBlockChecker, ChatRepositoryContract } from '../chat/types.js';
import type { RealtimeEvent } from './events.js';
import { eventConversationId, eventForMessage, isSensitiveFieldAbsent, REALTIME_LIMITS, safeUserId } from './events.js';
import { RealtimeDispatcher, type RealtimeConnection } from './dispatcher.js';
import type WebSocket from 'ws';

export interface RealtimePublisher {
  publishToUser(userId: string, event: RealtimeEvent): Promise<number>;
  publishToConversation(conversationId: string, event: RealtimeEvent): Promise<number>;
  messageCreated(conversationId: string, event: RealtimeEvent): Promise<number>;
  reactionChanged(conversationId: string, event: RealtimeEvent): Promise<number>;
  readStateChanged(conversationId: string, event: RealtimeEvent): Promise<number>;
}

export class RealtimeService implements RealtimePublisher {
  readonly dispatcher = new RealtimeDispatcher();
  private heartbeat?: NodeJS.Timeout;
  private closing = false;

  constructor(
    private readonly pool: Pool,
    private readonly chat: ChatRepositoryContract,
    private readonly blocks: ChatBlockChecker
  ) {}

  startHeartbeat(): void {
    if (this.heartbeat) return;
    this.heartbeat = setInterval(() => this.heartbeatTick(), REALTIME_LIMITS.heartbeatMs);
    this.heartbeat.unref();
  }

  heartbeatTick(now = Date.now()): void {
    for (const connection of this.dispatcher.getConnections()) {
      if (now - connection.lastPongAt >= REALTIME_LIMITS.staleAfterMs) {
        this.dispatcher.remove(connection);
        try { connection.socket.terminate(); } catch { /* already closed */ }
        continue;
      }
      if (connection.socket.readyState === 1) {
        try { connection.socket.ping(); } catch { this.dispatcher.remove(connection); }
      }
    }
  }

  register(socket: WebSocket, userId: string, sessionId: string): RealtimeConnection | null {
    if (this.closing) return null;
    return this.dispatcher.register(socket, safeUserId(userId), sessionId);
  }

  terminateSession(userId: string, sessionId: string): void {
    for (const socket of this.dispatcher.closeSession(userId, sessionId)) {
      const timeout = setTimeout(() => socket.terminate(), 1_000);
      timeout.unref();
    }
  }

  terminateUserSessions(userId: string): void {
    for (const socket of this.dispatcher.closeUserSessions(userId)) {
      const timeout = setTimeout(() => socket.terminate(), 1_000);
      timeout.unref();
    }
  }

  async authorizeChannel(userId: string, channel: 'user' | 'conversation', id: string): Promise<boolean> {
    if (channel === 'user') return userId === id.toLowerCase();
    try {
      if (!await this.chat.isActiveMember(this.pool, id, userId)) return false;
      const otherParticipants = await this.chat.getOtherParticipantIds(this.pool, id, userId);
      for (const participantId of otherParticipants) {
        if (await this.blocks.isBlocked(this.pool, userId, participantId)) return false;
      }
      return true;
    } catch {
      return false;
    }
  }

  async authorizeDelivery(connection: RealtimeConnection, channel: string): Promise<boolean> {
    const separator = channel.indexOf(':');
    if (separator < 0) return false;
    const kind = channel.slice(0, separator);
    const id = channel.slice(separator + 1);
    if (kind === 'user') return connection.userId === id;
    if (kind === 'conversation') return this.authorizeChannel(connection.userId, 'conversation', id);
    return false;
  }

  async publishToUser(userId: string, event: RealtimeEvent): Promise<number> {
    if (this.closing || event.event !== 'notification.created' || !isSensitiveFieldAbsent(event)) return 0;
    const normalized = safeUserId(userId);
    return this.dispatcher.publish(`user:${normalized}`, event, (connection, channel) =>
      Promise.resolve(connection.userId === normalized && channel === `user:${normalized}`)
    );
  }

  async publishToConversation(conversationId: string, event: RealtimeEvent): Promise<number> {
    if (this.closing || event.event === 'notification.created' || !isSensitiveFieldAbsent(event)) return 0;
    const normalized = safeUserId(conversationId);
    if (eventConversationId(event)?.toLowerCase() !== normalized) return 0;
    return this.dispatcher.publish(
      `conversation:${normalized}`,
      event,
      async (connection, channel) => channel === `conversation:${normalized}` && await this.authorizeDelivery(connection, channel),
      async connection => {
        if (event.event !== 'message.created') return event;
        const memberView = await this.chat.getMessageForMember(this.pool, event.data.message.id, connection.userId);
        return memberView ? eventForMessage(memberView) : null;
      }
    );
  }

  messageCreated(conversationId: string, event: RealtimeEvent): Promise<number> {
    return this.publishToConversation(conversationId, event);
  }

  reactionChanged(conversationId: string, event: RealtimeEvent): Promise<number> {
    return this.publishToConversation(conversationId, event);
  }

  readStateChanged(conversationId: string, event: RealtimeEvent): Promise<number> {
    return this.publishToConversation(conversationId, event);
  }

  async close(): Promise<void> {
    this.closing = true;
    if (this.heartbeat) clearInterval(this.heartbeat);
    this.heartbeat = undefined;
    const sockets = this.dispatcher.closeAll(1001, 'Server shutting down');
    await Promise.all(sockets.map(socket => new Promise<void>(resolve => {
      if (socket.readyState === 3) return resolve();
      const timeout = setTimeout(() => { try { socket.terminate(); } catch { /* already closed */ } resolve(); }, 1_500);
      timeout.unref();
      socket.once('close', () => { clearTimeout(timeout); resolve(); });
    })));
  }

}
