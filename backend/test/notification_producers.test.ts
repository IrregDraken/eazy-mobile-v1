import assert from 'node:assert/strict';
import test from 'node:test';
import { notifyComment, notifyFollow, notifyLike } from '../src/modules/notifications/producers/social.js';
import type { NotificationService } from '../src/modules/notifications/service.js';

function fakeDb() { return { query: async () => ({ rows: [{ id: 'notification-id' }], rowCount: 1 }) } as never; }

test('social notification producers pass trusted actor, recipient, and entity metadata', async () => {
  const calls: unknown[] = [];
  const notifications = { createInTransaction: async (_db: unknown, input: unknown) => { calls.push(input); return 'id'; } } as unknown as NotificationService;
  await notifyFollow(fakeDb(), notifications, 'actor', 'recipient');
  await notifyLike(fakeDb(), notifications, 'actor', 'recipient', 'post-id');
  await notifyComment(fakeDb(), notifications, 'actor', 'recipient', 'post-id');
  assert.deepEqual(calls, [
    { recipientUserId: 'recipient', actorUserId: 'actor', type: 'follow', entityType: 'user', entityId: 'recipient', title: 'New follower', body: 'Someone followed you' },
    { recipientUserId: 'recipient', actorUserId: 'actor', type: 'like', entityType: 'post', entityId: 'post-id', title: 'Post liked', body: 'Someone liked your post' },
    { recipientUserId: 'recipient', actorUserId: 'actor', type: 'comment', entityType: 'post', entityId: 'post-id', title: 'New comment', body: 'Someone commented on your post' }
  ]);
});
