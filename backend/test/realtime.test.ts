import assert from 'node:assert/strict';
import test from 'node:test';
import { createServer } from 'node:http';
import WebSocket from 'ws';
import { loadConfig } from '../src/config/env.js';
import { ChatService } from '../src/modules/chat/service.js';
import { NotificationService } from '../src/modules/notifications/service.js';
import { SocialService } from '../src/modules/social/service.js';
import { eventForNotification, type RealtimeEvent } from '../src/modules/realtime/events.js';
import { attachRealtimeGateway } from '../src/modules/realtime/connection.js';
import { RealtimeService } from '../src/modules/realtime/service.js';
import type { ChatMessage, ChatRepositoryContract } from '../src/modules/chat/types.js';
import type { FirebaseAuthProvider } from '../src/providers/firebase-auth.js';
import type { AuthService } from '../src/modules/auth/service.js';
import type { NotificationRepository, NotificationProjection } from '../src/modules/notifications/repository.js';
import type { SocialRepository } from '../src/modules/social/repository.js';

const userA = '00000000-0000-4000-8000-000000000001';
const userB = '00000000-0000-4000-8000-000000000002';
const userC = '00000000-0000-4000-8000-000000000003';
const conversationId = '10000000-0000-4000-8000-000000000001';
const messageId = '20000000-0000-4000-8000-000000000001';
const notificationId = '30000000-0000-4000-8000-000000000001';
const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent', CORS_ORIGIN: 'http://client.example', RATE_LIMIT_MAX: '100', RATE_LIMIT_WINDOW_MS: '60000' });

interface TestClient {
  socket: WebSocket;
  ready: unknown;
  queue: unknown[];
  waiters: Array<(value: unknown) => void>;
  next(predicate?: (value: unknown) => boolean): Promise<unknown>;
}

function makeMessage(user: string, reactedByMe: boolean): ChatMessage {
  return {
    id: messageId, conversationId,
    sender: { username: user === userA ? 'alice_1' : 'bob_22', displayName: user === userA ? 'Alice' : 'Bob', avatarUrl: null },
    body: 'A private message', status: 'sent', createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z',
    deletedAt: null, replyToMessageId: null, replyTo: null, attachments: [],
    reactions: [{ reaction: 'like', count: 1, reactedByMe }]
  };
}

const notification: NotificationProjection = {
  id: notificationId, type: 'follow', actor: { username: 'bob_22', displayName: 'Bob', avatarUrl: null },
  title: 'New follower', body: 'Someone followed you', entityType: 'user', entityId: userA,
  isRead: false, createdAt: '2026-01-01T00:00:00.000Z'
};

function fixture() {
  let blocked = false;
  const membership = new Map([[`${userA}:${conversationId}`, true], [`${userB}:${conversationId}`, true]]);
  const chat = {
    isActiveMember: async (_db: unknown, conversation: string, user: string) => membership.get(`${user}:${conversation}`) ?? false,
    getOtherParticipantIds: async (_db: unknown, conversation: string, user: string) => conversation === conversationId ? [user === userA ? userB : userA] : [],
    getMessageForMember: async (_db: unknown, id: string, user: string) => id === messageId && membership.get(`${user}:${conversationId}`) ? makeMessage(user, user === userB) : null
  } as unknown as ChatRepositoryContract;
  const blocks = { isBlocked: async () => blocked };
  const pool = { query: async () => ({ rows: [], rowCount: 0 }) } as never;
  const realtime = new RealtimeService(pool, chat, blocks);
  const provider = {
    verifyIdentity: async (token: string) => {
      if (token === 'invalid-token') throw Object.assign(new Error('provider secret must stay private'), { code: 'UNAUTHORIZED' });
      if (token === 'token-a') return { firebaseUid: 'firebase-user-a', claims: { email: 'private@example.com', auth_time: 1_760_000_000 } };
      if (token === 'token-b') return { firebaseUid: 'firebase-user-b', claims: { auth_time: 1_760_000_000 } };
      if (token === 'token-c') return { firebaseUid: 'firebase-user-c', claims: { auth_time: 1_760_000_000 } };
      throw Object.assign(new Error('invalid'), { code: 'UNAUTHORIZED' });
    }
  } as unknown as FirebaseAuthProvider;
  const users = new Map([['firebase-user-a', userA], ['firebase-user-b', userB], ['firebase-user-c', userC]]);
  const auth = {
    provision: async (identity: { firebaseUid: string }) => ({
      context: { userId: users.get(identity.firebaseUid) ?? userC, firebaseUid: identity.firebaseUid, sessionId: `session-${identity.firebaseUid}`, provider: 'firebase', claims: {} },
      record: { user: { status: 'active' } }
    })
  } as unknown as AuthService;
  return { pool, chat, realtime, provider, auth, membership, setBlocked(value: boolean) { blocked = value; } };
}

async function makeGateway() {
  const state = fixture();
  const server = createServer();
  const gateway = attachRealtimeGateway(server, config, state.provider, state.auth, state.realtime);
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  assert.ok(address && typeof address !== 'string');
  const endpoint = `ws://127.0.0.1:${address.port}/v1/realtime`;
  return {
    ...state, server, gateway, endpoint,
    async close() {
      await gateway.close();
      if (server.listening) await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    }
  };
}

function clientFor(socket: WebSocket): TestClient {
  const queue: unknown[] = [];
  const waiters: Array<(value: unknown) => void> = [];
  socket.on('message', data => {
    let value: unknown;
    try { value = JSON.parse(data.toString()) as unknown; } catch { value = data.toString(); }
    const waiter = waiters.shift();
    if (waiter) waiter(value); else queue.push(value);
  });
  return {
    socket, queue, waiters, ready: undefined,
    async next(predicate = () => true) {
      const deadline = Date.now() + 2_000;
      while (Date.now() < deadline) {
        const index = queue.findIndex(predicate);
        if (index >= 0) return queue.splice(index, 1)[0];
        const value = await new Promise<unknown>((resolve, reject) => {
          const timeout = setTimeout(() => reject(new Error('Timed out waiting for WebSocket message')), Math.max(1, deadline - Date.now()));
          waiters.push(item => { clearTimeout(timeout); resolve(item); });
        });
        if (predicate(value)) return value;
        queue.push(value);
      }
      throw new Error('Timed out waiting for WebSocket message');
    }
  };
}

async function connect(endpoint: string, token: string): Promise<TestClient> {
  const socket = new WebSocket(endpoint, { headers: { Authorization: `Bearer ${token}`, Origin: 'http://client.example' } });
  const client = clientFor(socket);
  await new Promise<void>((resolve, reject) => {
    socket.once('open', resolve);
    socket.once('error', reject);
  });
  const ready = await client.next(value => isRecord(value) && value.type === 'ready');
  assert.equal(isRecord(ready) && ready.type === 'ready', true);
  client.ready = ready;
  return client;
}

async function rejectedHandshake(endpoint: string, token?: string, path = '/v1/realtime', origin = 'http://client.example') {
  const socket = new WebSocket(`${endpoint.split('/v1/')[0]}${path}`, {
    ...(token ? { headers: { Authorization: `Bearer ${token}`, Origin: origin } } : { headers: { Origin: origin } })
  });
  const status = await new Promise<number>((resolve, reject) => {
    socket.once('unexpected-response', (_request, response) => { resolve(response.statusCode ?? 0); response.resume(); });
    socket.once('error', error => {
      if (error.message.includes('Unexpected server response')) return;
      reject(error);
    });
  });
  socket.terminate();
  return status;
}

function send(client: TestClient, value: unknown): void { client.socket.send(JSON.stringify(value)); }
function isRecord(value: unknown): value is Record<string, unknown> { return !!value && typeof value === 'object' && !Array.isArray(value); }

async function subscribe(client: TestClient, channel: 'user' | 'conversation', id: string) {
  send(client, { type: 'subscribe', channel, id });
  return client.next(value => isRecord(value) && (value.type === 'subscribed' || value.type === 'error'));
}

async function closed(socket: WebSocket): Promise<number> {
  if (socket.readyState === WebSocket.CLOSED) return socket.readyState;
  return new Promise(resolve => socket.once('close', code => resolve(code)));
}

test('WebSocket handshake requires a verified Firebase bearer token and uses its mapped Eazy identity', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  assert.equal(await rejectedHandshake(gateway.endpoint), 401);
  assert.equal(await rejectedHandshake(gateway.endpoint, 'invalid-token'), 401);
  const client = await connect(gateway.endpoint, 'token-a');
  t.after(() => client.socket.terminate());
  assert.deepEqual(client.ready, { type: 'ready', userId: userA });
  assert.notEqual(userA, 'firebase-user-a');
});

test('upgrade requires exact realtime path, empty query, and configured origin', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  assert.equal(await rejectedHandshake(gateway.endpoint, 'token-a', '/v1/realtime?token=secret'), 404);
  assert.equal(await rejectedHandshake(gateway.endpoint, 'token-a', '/v1/realtime', 'http://evil.example'), 403);
});

test('user channels are private to authenticated identity; strict client frames reject impersonation and wildcards', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  const client = await connect(gateway.endpoint, 'token-a');
  t.after(() => client.socket.terminate());
  assert.deepEqual(await subscribe(client, 'user', userA), { type: 'subscribed', channel: 'user', id: userA });
  assert.deepEqual(await subscribe(client, 'user', userB), { type: 'error', code: 'forbidden', message: 'This subscription is unavailable' });
  send(client, { type: 'subscribe', channel: 'conversation', id: '*' });
  assert.deepEqual(await client.next(value => isRecord(value) && value.type === 'error'), { type: 'error', code: 'invalid_subscription', message: 'Invalid realtime subscription' });
  send(client, { type: 'subscribe', channel: 'user', id: userB, userId: userB });
  assert.deepEqual(await client.next(value => isRecord(value) && value.type === 'error'), { type: 'error', code: 'invalid_subscription', message: 'Invalid realtime subscription' });
  send(client, { type: 'event', event: 'message.created', data: { message: {} } });
  assert.deepEqual(await client.next(value => isRecord(value) && value.type === 'error'), { type: 'error', code: 'invalid_message', message: 'Invalid realtime message' });
});

test('only active conversation members can subscribe; block changes revoke subscriptions before delivery', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  const a = await connect(gateway.endpoint, 'token-a');
  const b = await connect(gateway.endpoint, 'token-b');
  const c = await connect(gateway.endpoint, 'token-c');
  t.after(() => { a.socket.terminate(); b.socket.terminate(); c.socket.terminate(); });
  assert.deepEqual(await subscribe(a, 'conversation', conversationId), { type: 'subscribed', channel: 'conversation', id: conversationId });
  assert.deepEqual(await subscribe(b, 'conversation', conversationId), { type: 'subscribed', channel: 'conversation', id: conversationId });
  assert.deepEqual(await subscribe(c, 'conversation', conversationId), { type: 'error', code: 'not_found', message: 'This subscription is unavailable' });
  gateway.setBlocked(true);
  assert.equal(await gateway.realtime.publishToConversation(conversationId, { event: 'message.reaction.created', data: { conversationId, messageId, reaction: 'like' } }), 0);
  assert.equal(a.socket.readyState, WebSocket.OPEN);
  assert.equal(gateway.realtime.dispatcher.getConnections().find(connection => connection.userId === userA)?.channels.has(`conversation:${conversationId}`), false);
});

test('an async subscribe authorization cannot race and undo a later unsubscribe', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  const client = await connect(gateway.endpoint, 'token-a');
  t.after(() => client.socket.terminate());
  let release!: () => void;
  const blocked = new Promise<void>(resolve => { release = resolve; });
  const authorize = gateway.realtime.authorizeChannel.bind(gateway.realtime);
  gateway.realtime.authorizeChannel = async (...args) => { await blocked; return authorize(...args); };
  send(client, { type: 'subscribe', channel: 'conversation', id: conversationId });
  send(client, { type: 'unsubscribe', channel: 'conversation', id: conversationId });
  assert.deepEqual(await client.next(value => isRecord(value) && value.type === 'unsubscribed'), { type: 'unsubscribed', channel: 'conversation', id: conversationId });
  release();
  await new Promise(resolve => setTimeout(resolve, 5));
  assert.equal(gateway.realtime.dispatcher.getConnections()[0]?.channels.has(`conversation:${conversationId}`), false);
});

test('chat events reach active members only and message projections are rebuilt per recipient', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  const a = await connect(gateway.endpoint, 'token-a');
  const b = await connect(gateway.endpoint, 'token-b');
  const c = await connect(gateway.endpoint, 'token-c');
  t.after(() => { a.socket.terminate(); b.socket.terminate(); c.socket.terminate(); });
  await subscribe(a, 'conversation', conversationId);
  await subscribe(b, 'conversation', conversationId);
  await subscribe(c, 'user', userC);
  const senderView = makeMessage(userA, false);
  assert.equal(await gateway.realtime.publishToConversation(conversationId, { event: 'message.created', data: { message: senderView } }), 2);
  const receivedA = await a.next(value => isRecord(value) && value.type === 'event');
  const receivedB = await b.next(value => isRecord(value) && value.type === 'event');
  assert.equal(isRecord(receivedA) && isRecord(receivedA.data) && isRecord(receivedA.data.message) && Array.isArray(receivedA.data.message.reactions) && isRecord(receivedA.data.message.reactions[0]) && receivedA.data.message.reactions[0].reactedByMe, false);
  assert.equal(isRecord(receivedB) && isRecord(receivedB.data) && isRecord(receivedB.data.message) && Array.isArray(receivedB.data.message.reactions) && isRecord(receivedB.data.message.reactions[0]) && receivedB.data.message.reactions[0].reactedByMe, true);
  assert.deepEqual(Object.keys(receivedA as object).sort(), ['data', 'event', 'type']);
  assert.equal(JSON.stringify(receivedA).includes('firebaseUid'), false);
  assert.equal(JSON.stringify(receivedA).includes('firebase-user-a'), false);
  assert.equal(c.queue.some(value => isRecord(value) && value.type === 'event'), false);
  const reaction = { event: 'message.reaction.deleted' as const, data: { conversationId, messageId, reaction: 'like' } };
  assert.equal(await gateway.realtime.publishToConversation(conversationId, reaction), 2);
  assert.equal((await a.next(value => isRecord(value) && value.type === 'event') as { event: string }).event, 'message.reaction.deleted');
  assert.equal((await b.next(value => isRecord(value) && value.type === 'event') as { event: string }).event, 'message.reaction.deleted');
  const read = { event: 'message.read' as const, data: { conversationId, lastReadMessageId: messageId, readAt: '2026-01-03T00:00:00.000Z', reader: { username: 'alice_1', displayName: 'Alice', avatarUrl: null } } };
  assert.equal(await gateway.realtime.publishToConversation(conversationId, read), 2);
  assert.equal((await a.next(value => isRecord(value) && value.type === 'event') as { event: string }).event, 'message.read');
  assert.equal((await b.next(value => isRecord(value) && value.type === 'event') as { event: string }).event, 'message.read');
  gateway.membership.set(`${userA}:${conversationId}`, false);
  assert.equal(await gateway.realtime.publishToConversation(conversationId, reaction), 1);
});

test('notification events are scoped to recipient user channels and durable REST persistence does not depend on sockets', async () => {
  const gateway = await makeGateway();
  try {
    const a = await connect(gateway.endpoint, 'token-a');
    const b = await connect(gateway.endpoint, 'token-b');
    try {
      await subscribe(a, 'user', userA);
      await subscribe(b, 'user', userB);
      assert.equal(await gateway.realtime.publishToUser(userA, eventForNotification(notification)), 1);
      const delivered = await a.next(value => isRecord(value) && value.type === 'event');
      assert.equal(isRecord(delivered) && delivered.event, 'notification.created');
      assert.equal(JSON.stringify(delivered).includes('firebaseUid'), false);
      assert.equal(b.queue.some(value => isRecord(value) && value.type === 'event'), false);
    } finally { a.socket.terminate(); b.socket.terminate(); }

    let inserted = false;
    let committed = false;
    const published: unknown[] = [];
    const repository = {
      create: async () => { inserted = true; return notificationId; },
      get: async () => { assert.equal(committed, true); return notification; }
    } as unknown as NotificationRepository;
    const pool = {
      connect: async () => ({ query: async (sql: string) => { if (sql === 'COMMIT') committed = true; return { rows: [], rowCount: sql === 'COMMIT' ? 0 : 1 }; }, release: () => undefined })
    } as never;
    const notifications = new NotificationService(pool, repository, { publishToUser: async (userId: string, event: RealtimeEvent) => { assert.equal(userId, userA); published.push(event); return 0; } } as never);
    assert.equal(await notifications.create({ recipientUserId: userA, actorUserId: userB, type: 'follow' }), notificationId);
    assert.equal(inserted, true);
    assert.deepEqual((published[0] as { event: string }).event, 'notification.created');
  } finally { await gateway.close(); }
});

test('notifications created inside domain transactions are dispatched only after commit', async () => {
  let committed = false;
  let created = false;
  const published: unknown[] = [];
  const client = { query: async (sql: string) => { if (sql === 'COMMIT') committed = true; return { rows: [], rowCount: 0 }; }, release: () => undefined };
  const pool = { connect: async () => client, query: async () => ({ rows: [], rowCount: 0 }) } as never;
  const notificationRepo = {
    create: async () => { created = true; return notificationId; },
    get: async (userId: string, id: string) => {
      assert.equal(created, true);
      assert.equal(committed, true);
      assert.equal(userId, userB);
      assert.equal(id, notificationId);
      return notification;
    }
  } as unknown as NotificationRepository;
  const notifications = new NotificationService(pool, notificationRepo, {
    publishToUser: async (_userId: string, event: RealtimeEvent) => { assert.equal(committed, true); published.push(event); return 0; }
  } as never);
  const socialRepo = {
    targetByUsername: async () => ({ id: userB, username: 'bob_22' }),
    isBlocked: async () => false,
    follow: async () => true
  } as unknown as SocialRepository;
  const social = new SocialService(pool, socialRepo, notifications);
  assert.deepEqual(await social.follow(userA, 'bob_22'), { following: true, username: 'bob_22' });
  assert.equal(published.length, 1);
  assert.equal((published[0] as { event: string }).event, 'notification.created');
});

test('malformed and oversized client frames are rejected and malformed-frame abuse closes the connection', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  const malformedClient = await connect(gateway.endpoint, 'token-a');
  t.after(() => malformedClient.socket.terminate());
  malformedClient.socket.send('{');
  malformedClient.socket.send('{');
  malformedClient.socket.send('{');
  for (let index = 0; index < 3; index += 1) {
    assert.deepEqual(await malformedClient.next(value => isRecord(value) && value.type === 'error'), { type: 'error', code: 'invalid_message', message: 'Invalid realtime message' });
  }
  assert.equal(await closed(malformedClient.socket), 1008);
  const oversizedClient = await connect(gateway.endpoint, 'token-b');
  t.after(() => oversizedClient.socket.terminate());
  oversizedClient.socket.send(JSON.stringify({ type: 'unknown', payload: 'x'.repeat(5000) }));
  assert.equal(await closed(oversizedClient.socket), 1009);
});

test('per-connection frame rate limit closes abusive clients without accepting domain mutations', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  const client = await connect(gateway.endpoint, 'token-a');
  t.after(() => client.socket.terminate());
  const closedWithRateLimit = new Promise<number>(resolve => client.socket.once('close', code => resolve(code)));
  for (let index = 0; index < 121; index += 1) client.socket.send(JSON.stringify({ type: 'unsubscribe', channel: 'conversation', id: conversationId }));
  assert.equal(await closedWithRateLimit, 4429);
});

test('subscription changes are independently bounded', async t => {
  const gateway = await makeGateway();
  t.after(() => gateway.close());
  const client = await connect(gateway.endpoint, 'token-a');
  t.after(() => client.socket.terminate());
  const closedWithRateLimit = new Promise<number>(resolve => client.socket.once('close', code => resolve(code)));
  for (let index = 0; index < 61; index += 1) client.socket.send(JSON.stringify({ type: 'unsubscribe', channel: 'conversation', id: conversationId }));
  assert.equal(await closedWithRateLimit, 4429);
});

test('duplicate connections are bounded, disconnect cleanup permits reconnect, and heartbeat removes stale sockets', async t => {
  const gateway = await makeGateway();
  const clients: TestClient[] = [];
  t.after(() => { for (const client of clients) client.socket.terminate(); return gateway.close(); });
  for (let index = 0; index < 5; index += 1) clients.push(await connect(gateway.endpoint, 'token-a'));
  assert.equal(await rejectedHandshake(gateway.endpoint, 'token-a'), 429);
  const first = clients.shift()!;
  const firstClosed = new Promise<void>(resolve => first.socket.once('close', () => resolve()));
  first.socket.close(1000, 'test reconnect');
  await Promise.race([firstClosed, new Promise<never>((_resolve, reject) => setTimeout(() => reject(new Error('first connection close timed out')), 2_000))]);
  const reconnected = await connect(gateway.endpoint, 'token-a');
  clients.push(reconnected);
  const connection = gateway.realtime.dispatcher.getConnections().filter(item => item.userId === userA).at(-1)!;
  const pinged = new Promise<void>(resolve => reconnected.socket.once('ping', () => resolve()));
  gateway.realtime.heartbeatTick();
  await Promise.race([pinged, new Promise<never>((_resolve, reject) => setTimeout(() => reject(new Error('heartbeat ping timed out')), 2_000))]);
  connection.lastPongAt = Date.now() - 121_000;
  const staleClosed = new Promise<void>(resolve => reconnected.socket.once('close', () => resolve()));
  gateway.realtime.heartbeatTick();
  await Promise.race([staleClosed, new Promise<never>((_resolve, reject) => setTimeout(() => reject(new Error('stale socket close timed out')), 2_000))]);
  assert.equal(gateway.realtime.dispatcher.getConnections().filter(item => item.userId === userA).length, 4);
});

test('graceful gateway shutdown closes active WebSockets and clears registered connections', async () => {
  const gateway = await makeGateway();
  const client = await connect(gateway.endpoint, 'token-a');
  assert.equal(gateway.realtime.dispatcher.size, 1);
  await gateway.gateway.close();
  await closed(client.socket);
  assert.equal(gateway.realtime.dispatcher.size, 0);
  if (gateway.server.listening) await new Promise<void>((resolve, reject) => gateway.server.close(error => error ? reject(error) : resolve()));
});

test('ChatService continues to use existing database transactions for chat mutations before publishing', async () => {
  const statements: string[] = [];
  const message = makeMessage(userA, false);
  const repository = {
    lockDirectConversation: async () => undefined,
    isActiveMember: async () => true,
    getOtherParticipantIds: async () => [userB],
    replyBelongsToConversation: async () => true,
    createMessage: async () => messageId,
    getMessageForMember: async () => message
  } as unknown as ChatRepositoryContract;
  const pool = {
    connect: async () => ({ query: async (sql: string) => { statements.push(sql); return { rows: [], rowCount: 0 }; }, release: () => undefined })
  } as never;
  const realtime = { messageCreated: async () => { assert.equal(statements.at(-1), 'COMMIT'); return 1; } } as never;
  const service = new ChatService(pool, repository, { isBlocked: async () => false }, realtime);
  await service.sendMessage(userA, conversationId, { body: 'commit first' });
  assert.deepEqual(statements, ['BEGIN', 'COMMIT']);
});
