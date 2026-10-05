import assert from 'node:assert/strict';
import test from 'node:test';
import type { RequestHandler } from 'express';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { AppError } from '../src/middleware/errors.js';
import { createChatRouter } from '../src/modules/chat/routes.js';
import { ChatService } from '../src/modules/chat/service.js';
import { addReactionSchema, chatPaginationSchema, createConversationSchema, createMessageSchema, readStateSchema, reportMessageSchema, supportedReactions } from '../src/modules/chat/schemas.js';
import type { ChatBlockChecker, ChatConversation, ChatMessage, ChatRepositoryContract, ChatReadState } from '../src/modules/chat/types.js';
import type { RealtimePublisher } from '../src/modules/realtime/service.js';

const currentUser = '00000000-0000-4000-8000-000000000001';
const otherUser = '00000000-0000-4000-8000-000000000002';
const conversationId = '10000000-0000-4000-8000-000000000001';
const messageId = '20000000-0000-4000-8000-000000000001';
const replyId = '20000000-0000-4000-8000-000000000002';
const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

function fakePool() {
  const client = { query: async () => ({ rows: [], rowCount: 0 }), release: () => undefined };
  return { connect: async () => client } as never;
}

function makeConversation(id = conversationId): ChatConversation {
  return { id, kind: 'direct', createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z', participants: [{ username: 'alice_1', displayName: 'Alice', avatarUrl: null }, { username: 'bob_22', displayName: 'Bob', avatarUrl: null }], latestMessage: null, unreadCount: 0, lastReadAt: null };
}

function makeMessage(overrides: Partial<ChatMessage> = {}): ChatMessage {
  return { id: messageId, conversationId, sender: { username: 'alice_1', displayName: 'Alice', avatarUrl: null }, body: 'hello', status: 'sent', createdAt: '2026-01-01T00:00:00.000Z', updatedAt: '2026-01-01T00:00:00.000Z', deletedAt: null, replyToMessageId: null, replyTo: null, attachments: [], reactions: [], ...overrides };
}

function harness(realtime?: RealtimePublisher) {
  const state = {
    blocked: false,
    member: true,
    target: { id: otherUser, username: 'bob_22' as string } as { id: string; username: string } | null,
    conversation: makeConversation(),
    message: makeMessage(),
    messageOwner: true,
    deleted: false,
    edited: false,
    reactionExists: false,
    lastRead: null as ChatReadState | null,
    createdBy: '' as string,
    createdBody: '' as string,
    createdReply: undefined as string | undefined,
    markedBy: '' as string,
    lockKeys: [] as string[],
    createCount: 0,
    pageArgs: [] as number[]
  };
  const repository = {
    findTargetByUsername: async (_client: unknown, username: string) => state.target?.username === username ? state.target : null,
    lockDirectConversation: async (_client: unknown, firstId: string, secondId: string) => { state.lockKeys.push(`direct:${firstId}:${secondId}`); },
    findDirectConversation: async () => state.createCount > 0 ? conversationId : null,
    createDirectConversation: async (_client: unknown, creatorId: string) => { state.createdBy = creatorId; state.createCount++; return conversationId; },
    isActiveMember: async () => state.member,
    getOtherParticipantIds: async () => [otherUser],
    getActiveParticipantProfile: async () => ({ username: 'alice_1', displayName: 'Alice', avatarUrl: null }),
    listConversations: async (_userId: string, page: number, limit: number) => { state.pageArgs = [page, limit]; return { items: [state.conversation], total: 1 }; },
    getConversation: async (_userId: string, id: string) => id === conversationId && state.member ? state.conversation : null,
    listMessages: async (_userId: string, _conversationId: string, page: number, limit: number) => { state.pageArgs = [page, limit]; return { items: [state.message], total: 1 }; },
    getMessageForMember: async (_client: unknown, id: string) => id === messageId && state.member ? state.message : null,
    replyBelongsToConversation: async (_client: unknown, id: string) => id === replyId,
    createMessage: async (_client: unknown, _cid: string, senderId: string, body: string, reply?: string) => { state.createdBy = senderId; state.createdBody = body; state.createdReply = reply; return messageId; },
    getMessageAsSender: async (_client: unknown, id: string, senderId: string) => id === messageId && senderId === currentUser && state.messageOwner ? { id, status: state.message.status, deletedAt: state.message.deletedAt } : null,
    softDeleteMessage: async () => { state.deleted = true; state.message = makeMessage({ body: null, status: 'deleted', deletedAt: '2026-01-02T00:00:00.000Z' }); return true; },
    editMessage: async (_client: unknown, _id: string, _userId: string, body: string) => { state.edited = true; state.message = makeMessage({ body, status: 'edited' }); return true; },
    getLatestMessageId: async () => messageId,
    markRead: async (_client: unknown, _cid: string, userId: string, id: string | null) => { state.markedBy = userId; state.lastRead = { conversationId, lastReadMessageId: id, readAt: '2026-01-03T00:00:00.000Z' }; return state.lastRead; },
    addReaction: async () => { const isNew = !state.reactionExists; state.reactionExists = true; return isNew; },
    removeReaction: async () => { const existed = state.reactionExists; state.reactionExists = false; return existed; },
    getMessageConversationForMember: async () => conversationId,
    createMessageReport: async () => 'report-id'
  } as unknown as ChatRepositoryContract;
  const blocks: ChatBlockChecker = { isBlocked: async () => state.blocked };
  const service = new ChatService(fakePool(), repository, blocks, realtime);
  return { state, repository, service };
}

async function withServer(run: (baseUrl: string) => Promise<void>) {
  const { service } = harness();
  const auth: RequestHandler = (request, _response, next) => {
    if (request.header('authorization') === 'Bearer test-token') request.auth = { userId: currentUser, provider: 'test', claims: {} };
    next();
  };
  const app = createApp(config, createLogger(config), { authMiddleware: auth, chatRouter: createChatRouter(service) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
}

const mustReject = async (operation: () => Promise<unknown>, code: AppError['code']) => {
  await assert.rejects(operation, (error: unknown) => error instanceof AppError && error.code === code);
};

test('conversation input is strict and normalizes the target username', () => {
  assert.deepEqual(createConversationSchema.parse({ username: '  BOB_22 ' }), { username: 'bob_22' });
  assert.throws(() => createConversationSchema.parse({ username: 'bob_22', members: [currentUser] }));
  assert.throws(() => createConversationSchema.parse({ username: 'a' }));
});

test('direct conversation creation uses authenticated actor, normalized pair lock, and returns idempotently', async () => {
  const { service, state } = harness();
  const first = await service.createConversation(currentUser, 'BOB_22');
  assert.equal(first.created, true);
  assert.equal(state.createdBy, currentUser);
  assert.deepEqual(state.lockKeys, ['direct:00000000-0000-4000-8000-000000000001:00000000-0000-4000-8000-000000000002']);
  const second = await service.createConversation(currentUser, 'bob_22');
  assert.equal(second.created, false);
  assert.equal(state.createCount, 1);
});

test('self conversations and missing target users are rejected', async () => {
  const { service, state } = harness();
  state.target = { id: currentUser, username: 'alice_1' };
  await mustReject(() => service.createConversation(currentUser, 'alice_1'), 'BAD_REQUEST');
  state.target = null;
  await mustReject(() => service.createConversation(currentUser, 'nobody_22'), 'NOT_FOUND');
});

test('blocked participants cannot create a direct conversation', async () => {
  const { service, state } = harness();
  state.blocked = true;
  await mustReject(() => service.createConversation(currentUser, 'bob_22'), 'FORBIDDEN');
  assert.equal(state.createCount, 0);
});

test('conversation detail and message pagination are scoped and deterministic page inputs are passed through', async () => {
  const { service, state } = harness();
  assert.equal((await service.getConversation(currentUser, conversationId)).conversation.id, conversationId);
  const page = await service.listMessages(currentUser, conversationId, { page: 2, limit: 50, cursor: undefined });
  assert.deepEqual(state.pageArgs, [2, 50]);
  assert.deepEqual(page.meta, { page: 2, limit: 50, cursor: null, total: 1, pages: 1 });
  state.member = false;
  await mustReject(() => service.getConversation(currentUser, conversationId), 'NOT_FOUND');
});

test('message body validation trims whitespace, preserves Unicode, and enforces the character bound', async () => {
  assert.deepEqual(createMessageSchema.parse({ body: ' こんにちは 🌍 ' }), { body: 'こんにちは 🌍' });
  assert.throws(() => createMessageSchema.parse({ body: ' \n ' }));
  assert.throws(() => createMessageSchema.parse({ body: 'x'.repeat(10_001) }));
  assert.throws(() => createMessageSchema.parse({ body: 'hello', sender_id: otherUser }));
  assert.throws(() => createMessageSchema.parse({ body: 'hello', attachments: [{ storageKey: 'arbitrary' }] }));
});

test('message sender is always derived from the authenticated actor', async () => {
  const { service, state } = harness();
  await service.sendMessage(currentUser, conversationId, { body: '  hello  ' });
  assert.equal(state.createdBy, currentUser);
  assert.equal(state.createdBody, 'hello');
});

test('committed messages, reaction changes, and read markers publish server-authored events', async () => {
  const events: unknown[] = [];
  const realtime = {
    publishToUser: async () => 0,
    publishToConversation: async () => 0,
    messageCreated: async (_conversation: string, event: unknown) => { events.push(event); return 1; },
    reactionChanged: async (_conversation: string, event: unknown) => { events.push(event); return 1; },
    readStateChanged: async (_conversation: string, event: unknown) => { events.push(event); return 1; }
  } as RealtimePublisher;
  const { service } = harness(realtime);
  assert.equal((await service.sendMessage(currentUser, conversationId, { body: 'live after commit' })).message.id, messageId);
  assert.deepEqual(await service.addReaction(currentUser, messageId, 'like'), { added: true });
  assert.deepEqual(await service.removeReaction(currentUser, messageId, 'like'), { removed: true });
  assert.equal((await service.markRead(currentUser, conversationId)).read?.conversationId, conversationId);
  assert.deepEqual(events.map(event => (event as { event: string }).event), [
    'message.created', 'message.reaction.created', 'message.reaction.deleted', 'message.read'
  ]);
  assert.deepEqual((events[3] as { data: { reader: unknown } }).data.reader, { username: 'alice_1', displayName: 'Alice', avatarUrl: null });
});

test('realtime transport failure cannot fail a successful chat write', async () => {
  const realtime = {
    publishToUser: async () => 0,
    publishToConversation: async () => 0,
    messageCreated: async () => { throw new Error('socket unavailable'); },
    reactionChanged: async () => { throw new Error('socket unavailable'); },
    readStateChanged: async () => { throw new Error('socket unavailable'); }
  } as RealtimePublisher;
  const { service, state } = harness(realtime);
  assert.equal((await service.sendMessage(currentUser, conversationId, { body: 'persisted first' })).message.id, messageId);
  assert.equal(state.createdBody, 'persisted first');
});

test('non-members, blocked users, and cross-conversation replies cannot send messages', async () => {
  const { service, state } = harness();
  state.member = false;
  await mustReject(() => service.sendMessage(currentUser, conversationId, { body: 'hi' }), 'NOT_FOUND');
  state.member = true;
  state.blocked = true;
  await mustReject(() => service.sendMessage(currentUser, conversationId, { body: 'hi' }), 'FORBIDDEN');
  state.blocked = false;
  await mustReject(() => service.sendMessage(currentUser, conversationId, { body: 'hi', replyToMessageId: messageId }), 'BAD_REQUEST');
});

test('same-conversation replies are allowed', async () => {
  const { service, state } = harness();
  await service.sendMessage(currentUser, conversationId, { body: 'answer', replyToMessageId: replyId });
  assert.equal(state.createdReply, replyId);
});

test('message deletion is soft, repeatable, and restricted to the sender', async () => {
  const { service, state } = harness();
  state.messageOwner = false;
  await mustReject(() => service.deleteMessage(currentUser, messageId), 'FORBIDDEN');
  state.messageOwner = true;
  const result = await service.deleteMessage(currentUser, messageId);
  assert.equal(result.deleted, true);
  assert.equal(state.deleted, true);
  const repeated = await service.deleteMessage(currentUser, messageId);
  assert.equal(repeated.deleted, true);
});

test('editing uses the existing edited status and is sender-owned only', async () => {
  const { service, state } = harness();
  state.messageOwner = false;
  await mustReject(() => service.editMessage(currentUser, messageId, 'new body'), 'FORBIDDEN');
  state.messageOwner = true;
  const result = await service.editMessage(currentUser, messageId, 'new body');
  assert.equal(result.message.status, 'edited');
  assert.equal(state.edited, true);
  state.message = makeMessage({ status: 'deleted', body: null });
  await mustReject(() => service.editMessage(currentUser, messageId, 'new body'), 'CONFLICT');
});

test('reactions validate a controlled set and are user-scoped and safe to repeat', async () => {
  assert.equal(addReactionSchema.parse({ reaction: '👍' }).reaction, '👍');
  assert.throws(() => addReactionSchema.parse({ reaction: 'unbounded-reaction' }));
  assert.ok(supportedReactions.length > 0);
  const { service, state } = harness();
  assert.equal((await service.addReaction(currentUser, messageId, '👍')).added, true);
  assert.equal((await service.addReaction(currentUser, messageId, '👍')).added, false);
  assert.equal((await service.removeReaction(currentUser, messageId, '👍')).removed, true);
  assert.equal((await service.removeReaction(currentUser, messageId, '👍')).removed, false);
  state.member = false;
  await mustReject(() => service.addReaction(currentUser, messageId, '👍'), 'NOT_FOUND');
});

test('read markers use only the authenticated user and are idempotent', async () => {
  const { service, state } = harness();
  const first = await service.markRead(currentUser, conversationId);
  const second = await service.markRead(currentUser, conversationId, messageId);
  assert.equal(state.markedBy, currentUser);
  assert.equal(first.read.lastReadMessageId, messageId);
  assert.equal(second.read.lastReadMessageId, messageId);
  assert.deepEqual(readStateSchema.parse({ lastReadMessageId: messageId }), { lastReadMessageId: messageId });
  assert.throws(() => readStateSchema.parse({ last_read_at: '2099-01-01T00:00:00Z' }));
  state.member = false;
  await mustReject(() => service.markRead(currentUser, conversationId), 'NOT_FOUND');
});

test('chat REST routes reject unauthenticated calls and malformed message payloads', async () => {
  await withServer(async baseUrl => {
    const anonymous = await fetch(`${baseUrl}/v1/chat/conversations`);
    assert.equal(anonymous.status, 401);
    const unauthenticatedCreate = await fetch(`${baseUrl}/v1/chat/conversations`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ username: 'bob_22' }) });
    assert.equal(unauthenticatedCreate.status, 401);
    const spoofed = await fetch(`${baseUrl}/v1/chat/conversations/${conversationId}/messages`, { method: 'POST', headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' }, body: JSON.stringify({ body: 'hello', sender_id: otherUser }) });
    assert.equal(spoofed.status, 422);
    const empty = await fetch(`${baseUrl}/v1/chat/conversations/${conversationId}/messages`, { method: 'POST', headers: { authorization: 'Bearer test-token', 'content-type': 'application/json' }, body: JSON.stringify({ body: '   ' }) });
    assert.equal(empty.status, 422);
  });
});

test('authenticated conversation creation and listing return the stable mobile projection', async () => {
  await withServer(async baseUrl => {
    const headers = { authorization: 'Bearer test-token', 'content-type': 'application/json' };
    const created = await fetch(`${baseUrl}/v1/chat/conversations`, { method: 'POST', headers, body: JSON.stringify({ username: 'bob_22' }) });
    assert.equal(created.status, 201);
    const createData = await created.json();
    assert.equal(createData.data.conversation.id, conversationId);
    assert.equal('firebaseUid' in createData.data.conversation, false);
    const listed = await fetch(`${baseUrl}/v1/chat/conversations?page=1&limit=50`, { headers });
    assert.equal(listed.status, 200);
    const listData = await listed.json();
    assert.equal(listData.data.items[0].participants[0].username, 'alice_1');
    assert.equal(listData.data.meta.limit, 50);
  });
});

test('chat backend does not trust client unread or read state fields', async () => {
  assert.throws(() => readStateSchema.parse({ lastReadMessageId: messageId, userId: otherUser }));
  assert.throws(() => createConversationSchema.parse({ username: 'bob_22', unreadCount: 99 }));
  assert.throws(() => chatPaginationSchema.parse({ cursor: messageId }));
});

test('chat reports validate reason and use the shared reports service path', async () => {
  assert.equal(reportMessageSchema.parse({ reason: '  abuse  ' }).reason, 'abuse');
  assert.throws(() => reportMessageSchema.parse({ reason: 'x' }));
  const { service } = harness();
  const report = await service.reportMessage(currentUser, messageId, 'abuse');
  assert.deepEqual(report, { submitted: true, reportId: 'report-id' });
});
