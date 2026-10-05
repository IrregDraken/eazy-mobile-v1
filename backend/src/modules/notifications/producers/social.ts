import type { DbClient } from '../../../database/client.js';
import type { NotificationService } from '../service.js';

export async function notifyFollow(db: DbClient, notifications: NotificationService, actorUserId: string, recipientUserId: string) {
  return notifications.createInTransaction(db, { recipientUserId, actorUserId, type: 'follow', entityType: 'user', entityId: recipientUserId, title: 'New follower', body: 'Someone followed you' });
}

export async function notifyLike(db: DbClient, notifications: NotificationService, actorUserId: string, recipientUserId: string, postId: string) {
  return notifications.createInTransaction(db, { recipientUserId, actorUserId, type: 'like', entityType: 'post', entityId: postId, title: 'Post liked', body: 'Someone liked your post' });
}

export async function notifyComment(db: DbClient, notifications: NotificationService, actorUserId: string, recipientUserId: string, postId: string) {
  return notifications.createInTransaction(db, { recipientUserId, actorUserId, type: 'comment', entityType: 'post', entityId: postId, title: 'New comment', body: 'Someone commented on your post' });
}
