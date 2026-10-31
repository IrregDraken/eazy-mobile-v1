import assert from 'node:assert/strict';
import test from 'node:test';
import { NotificationService } from '../src/modules/notifications/service.js';
import type { NotificationRepository } from '../src/modules/notifications/repository.js';
import { deviceRegistrationSchema } from '../src/modules/notifications/schemas.js';
import type { NotificationInput } from '../src/modules/notifications/repository.js';

function fakePool() {
  const client = { query: async () => undefined, release: () => undefined };
  return { connect: async () => client } as never;
}

test('notification creation suppresses self-notifications centrally', async () => {
  let created = false;
  const repository = { create: async () => { created = true; return 'id'; } } as unknown as NotificationRepository;
  const service = new NotificationService(fakePool(), repository);
  const result = await service.create({ recipientUserId: 'same', actorUserId: 'same', type: 'like', entityType: 'post', entityId: 'post' });
  assert.equal(result, null);
  assert.equal(created, false);
});

test('notification repository contract accepts only deterministic supported event fields', () => {
  const input: NotificationInput = { recipientUserId: 'recipient', actorUserId: 'actor', type: 'comment', entityType: 'post', entityId: 'post', title: 'New comment', body: 'Someone commented' };
  assert.equal(input.type, 'comment');
  assert.throws(() => deviceRegistrationSchema.parse({ token: 'short', platform: 'ios' }));
  assert.deepEqual(deviceRegistrationSchema.parse({ token: 'device-token-123456', platform: 'android' }), { token: 'device-token-123456', platform: 'android' });
});

test('notification list and unread state are recipient scoped', async () => {
  const repository = {
    list: async (userId: string) => ({ items: [{ id: 'notification-id', type: 'follow', actor: null, title: null, body: null, entityType: 'user', entityId: userId, isRead: false, createdAt: '2026-01-01T00:00:00Z' }], total: 1 }),
    get: async (userId: string) => userId === 'user-a' ? { id: 'notification-id', type: 'follow', actor: null, title: null, body: null, entityType: 'user', entityId: null, isRead: false, createdAt: '2026-01-01T00:00:00Z' } : null,
    markRead: async (userId: string) => userId === 'user-a',
    markAllRead: async () => 2,
    unreadCount: async () => 2
  } as unknown as NotificationRepository;
  const service = new NotificationService(fakePool(), repository);
  assert.equal((await service.list('user-a', { page: 1, limit: 20 })).items[0]!.id, 'notification-id');
  assert.equal((await service.unreadCount('user-a')).unreadCount, 2);
  await assert.rejects(() => service.get('user-b', 'notification-id'));
  await assert.rejects(() => service.markRead('user-b', 'notification-id'));
});

test('push delivery remains explicitly unavailable without provider credentials', async () => {
  const repository = { registerDevice: async () => 'device-id' } as unknown as NotificationRepository;
  const service = new NotificationService(fakePool(), repository);
  assert.equal((await service.registerDevice('user-a', { token: 'device-token-123456', platform: 'web' })).pushDelivery, 'unavailable');
});


test('transaction-created social notifications are pushed after commit without realtime', async () => {
  const sent: Array<{ userId: string; title: string; body: string }> = [];
  const notification = {
    id: 'notification-id',
    type: 'like',
    actor: null,
    title: 'Post liked',
    body: 'Someone liked your post',
    entityType: 'post',
    entityId: 'post-id',
    isRead: false,
    createdAt: '2026-10-31T00:00:00.000Z'
  };
  const repository = {
    create: async () => 'notification-id',
    get: async (userId: string, id: string) =>
      userId === 'recipient' && id === 'notification-id' ? notification : null
  } as unknown as NotificationRepository;
  const push = { notify: async (input: { userId: string; title: string; body: string }) => { sent.push(input); } };
  const service = new NotificationService(fakePool(), repository, undefined, push);
  const id = await service.createInTransaction({} as never, {
    recipientUserId: 'recipient',
    actorUserId: 'actor',
    type: 'like',
    entityType: 'post',
    entityId: 'post-id',
    title: 'Post liked',
    body: 'Someone liked your post'
  });
  assert.equal(id, 'notification-id');
  await service.publishCreated('recipient', id!);
  assert.deepEqual(sent, [{ userId: 'recipient', title: 'Post liked', body: 'Someone liked your post' }]);
});

test('order and payment notifications stay wallet-only and are not sent to device push', async () => {
  for (const type of ['order', 'payment'] as const) {
    const sent: string[] = [];
    const repository = {
      get: async () => ({
        id: 'financial-notification',
        type,
        actor: null,
        title: 'Wallet update',
        body: 'A financial event occurred',
        entityType: 'transaction',
        entityId: 'transaction-id',
        isRead: false,
        createdAt: '2026-10-31T00:00:00.000Z'
      })
    } as unknown as NotificationRepository;
    const push = { notify: async (input: { userId: string }) => { sent.push(input.userId); } };
    const service = new NotificationService(fakePool(), repository, undefined, push);
    await service.publishCreated('recipient', 'financial-notification');
    assert.deepEqual(sent, []);
  }
});

test('ordinary notification creation dispatches push exactly once', async () => {
  const sent: string[] = [];
  const notification = {
    id: 'notification-id',
    type: 'message',
    actor: null,
    title: 'New message',
    body: 'Hello',
    entityType: 'conversation',
    entityId: 'conversation-id',
    isRead: false,
    createdAt: '2026-10-31T00:00:00.000Z'
  };
  const repository = {
    create: async () => 'notification-id',
    get: async () => notification
  } as unknown as NotificationRepository;
  const push = { notify: async (input: { userId: string }) => { sent.push(input.userId); } };
  const service = new NotificationService(fakePool(), repository, undefined, push);
  const id = await service.create({
    recipientUserId: 'recipient',
    actorUserId: 'actor',
    type: 'message',
    entityType: 'conversation',
    entityId: 'conversation-id',
    title: 'New message',
    body: 'Hello'
  });
  assert.equal(id, 'notification-id');
  assert.deepEqual(sent, ['recipient']);
});
