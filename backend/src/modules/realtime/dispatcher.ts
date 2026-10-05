import { randomUUID } from 'node:crypto';
import WebSocket from 'ws';
import type { RealtimeEvent } from './events.js';
import { eventEnvelope, isSensitiveFieldAbsent } from './events.js';

export interface RealtimeConnection {
  id: string;
  userId: string;
  sessionId: string;
  socket: WebSocket;
  channels: Set<string>;
  isAlive: boolean;
  lastPongAt: number;
  frameWindowStartedAt: number;
  framesInWindow: number;
  subscriptionWindowStartedAt: number;
  subscriptionsInWindow: number;
  malformedFrames: number;
  operationSequence: number;
  pendingSubscriptionOperations: Map<string, number>;
  closed: boolean;
}

export type DeliveryAuthorizer = (connection: RealtimeConnection, channel: string) => Promise<boolean>;
export type EventProjector = (connection: RealtimeConnection, event: RealtimeEvent) => Promise<RealtimeEvent | null>;
const maxBufferedBytesPerConnection = 1_048_576;

export class RealtimeDispatcher {
  private readonly connections = new Map<string, RealtimeConnection>();
  private readonly byUser = new Map<string, Set<string>>();

  register(socket: WebSocket, userId: string, sessionId: string): RealtimeConnection | null {
    const userConnections = this.byUser.get(userId) ?? new Set<string>();
    if (userConnections.size >= 5) return null;
    const connection: RealtimeConnection = {
      id: randomUUID(), userId, sessionId, socket, channels: new Set(), isAlive: true,
      lastPongAt: Date.now(), frameWindowStartedAt: Date.now(), framesInWindow: 0,
      subscriptionWindowStartedAt: Date.now(), subscriptionsInWindow: 0,
      malformedFrames: 0, operationSequence: 0, pendingSubscriptionOperations: new Map(), closed: false
    };
    userConnections.add(connection.id);
    this.byUser.set(userId, userConnections);
    this.connections.set(connection.id, connection);
    return connection;
  }

  getConnection(id: string): RealtimeConnection | undefined { return this.connections.get(id); }

  subscribe(connection: RealtimeConnection, channel: string, maxSubscriptions: number): boolean {
    if (connection.closed) return false;
    if (connection.channels.has(channel)) return true;
    if (connection.channels.size >= maxSubscriptions) return false;
    connection.channels.add(channel);
    return true;
  }

  unsubscribe(connection: RealtimeConnection, channel: string): void {
    this.beginSubscriptionOperation(connection, channel);
    connection.channels.delete(channel);
  }

  beginSubscriptionOperation(connection: RealtimeConnection, channel: string): number {
    connection.operationSequence += 1;
    connection.pendingSubscriptionOperations.set(channel, connection.operationSequence);
    return connection.operationSequence;
  }

  isLatestSubscriptionOperation(connection: RealtimeConnection, channel: string, sequence: number): boolean {
    return !connection.closed && connection.pendingSubscriptionOperations.get(channel) === sequence;
  }

  finishSubscriptionOperation(connection: RealtimeConnection, channel: string, sequence: number): void {
    if (connection.pendingSubscriptionOperations.get(channel) === sequence) connection.pendingSubscriptionOperations.delete(channel);
  }

  async publish(channel: string, event: RealtimeEvent, authorize: DeliveryAuthorizer, project?: EventProjector): Promise<number> {
    try { eventEnvelope(event); } catch { return 0; }
    const recipients = [...this.connections.values()].filter(connection => connection.channels.has(channel) && !connection.closed);
    let delivered = 0;
    for (const connection of recipients) {
      if (connection.socket.readyState !== WebSocket.OPEN) {
        this.remove(connection);
        continue;
      }
      let allowed = false;
      try { allowed = await authorize(connection, channel); }
      catch { allowed = false; }
      if (!allowed) {
        this.unsubscribe(connection, channel);
        continue;
      }
      let projected: RealtimeEvent | null;
      try { projected = project ? await project(connection, event) : event; }
      catch { continue; }
      if (!projected || !isSensitiveFieldAbsent(projected)) continue;
      let payload: string;
      try { payload = JSON.stringify(eventEnvelope(projected)); }
      catch { continue; }
      if (connection.socket.bufferedAmount > maxBufferedBytesPerConnection) {
        this.remove(connection);
        try { connection.socket.terminate(); } catch { /* already closed */ }
        continue;
      }
      try {
        connection.socket.send(payload);
        delivered += 1;
      } catch {
        this.remove(connection);
        try { connection.socket.terminate(); } catch { /* already closed */ }
      }
    }
    return delivered;
  }

  remove(connection: RealtimeConnection): void {
    if (connection.closed) return;
    connection.closed = true;
    connection.channels.clear();
    connection.pendingSubscriptionOperations.clear();
    this.connections.delete(connection.id);
    const userConnections = this.byUser.get(connection.userId);
    userConnections?.delete(connection.id);
    if (userConnections?.size === 0) this.byUser.delete(connection.userId);
  }

  closeAll(code = 1001, reason = 'Server shutting down'): WebSocket[] {
    const sockets: WebSocket[] = [];
    for (const connection of this.connections.values()) {
      connection.channels.clear();
      if (connection.socket.readyState === WebSocket.OPEN || connection.socket.readyState === WebSocket.CONNECTING) {
        sockets.push(connection.socket);
        try { connection.socket.close(code, reason); } catch { connection.socket.terminate(); }
      }
      this.remove(connection);
    }
    return sockets;
  }

  closeSession(userId: string, sessionId: string, code = 1008, reason = 'Session revoked'): WebSocket[] {
    const sockets: WebSocket[] = [];
    for (const connection of this.connections.values()) {
      if (connection.userId !== userId || connection.sessionId !== sessionId) continue;
      connection.channels.clear();
      if (connection.socket.readyState === WebSocket.OPEN || connection.socket.readyState === WebSocket.CONNECTING) {
        sockets.push(connection.socket);
        try { connection.socket.close(code, reason); } catch { connection.socket.terminate(); }
      }
      this.remove(connection);
    }
    return sockets;
  }

  closeUserSessions(userId: string, code = 1008, reason = 'Sessions revoked'): WebSocket[] {
    const sockets: WebSocket[] = [];
    for (const connection of this.connections.values()) {
      if (connection.userId !== userId) continue;
      connection.channels.clear();
      if (connection.socket.readyState === WebSocket.OPEN || connection.socket.readyState === WebSocket.CONNECTING) {
        sockets.push(connection.socket);
        try { connection.socket.close(code, reason); } catch { connection.socket.terminate(); }
      }
      this.remove(connection);
    }
    return sockets;
  }

  get size(): number { return this.connections.size; }
  getConnectionCountForUser(userId: string): number { return this.byUser.get(userId)?.size ?? 0; }
  getConnections(): readonly RealtimeConnection[] { return [...this.connections.values()]; }
}
