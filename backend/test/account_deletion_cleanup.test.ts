import assert from 'node:assert/strict';
import test from 'node:test';
import { AccountDeletionService, type MediaDeleter } from '../src/modules/auth/account-deletion.js';

const userId = '00000000-0000-4000-8000-0000000000a1';

type State = { deleted: boolean; job: 'pending' | 'running' | 'failed' | 'complete'; media: { key: string; status: 'pending' | 'failed' | 'deleted' }[] };
function fakeDeletionPool(state: State) {
  const sqlLog: string[] = [];
  const query = async (sql: string, values?: unknown[]) => {
    sqlLog.push(sql.replace(/\s+/g, ' ').trim());
    if (sql.includes('FROM users WHERE')) return { rows: [{ firebase_uid: 'firebase-u1', email: state.deleted ? null : 'u1@example.test', status: state.deleted ? 'deleted' : 'active' }], rowCount: 1 };
    if (sql.includes('AS balance')) return { rows: [{ balance: '0', pending: '0', orders: '0', sales: '0' }], rowCount: 1 };
    if (sql.includes('SELECT storage_key FROM (')) return { rows: state.media.map(item => ({ storage_key: item.key })), rowCount: state.media.length };
    if (sql.includes('INSERT INTO account_deletion_jobs')) { state.job = 'pending'; return { rows: [], rowCount: 1 }; }
    if (sql.includes('INSERT INTO account_deletion_media')) return { rows: [], rowCount: 1 };
    if (sql.includes('SELECT firebase_uid, identity_deleted, status') && sql.includes('FROM account_deletion_jobs')) return { rows: [{ firebase_uid: 'firebase-u1', identity_deleted: state.job === 'complete', status: state.job, updated_at: new Date().toISOString() }], rowCount: 1 };
    if (sql.includes('SELECT storage_key FROM account_deletion_media')) return { rows: state.media.filter(item => item.status !== 'deleted').map(item => ({ storage_key: item.key })), rowCount: state.media.filter(item => item.status !== 'deleted').length };
    if (sql.includes("UPDATE users SET status = 'deleted'")) { state.deleted = true; return { rows: [], rowCount: 1 }; }
    if (sql.includes("UPDATE account_deletion_media SET status = 'deleted'")) { state.media.forEach(item => { item.status = 'deleted'; }); return { rows: [], rowCount: state.media.length }; }
    if (sql.includes("UPDATE account_deletion_media SET status = 'failed'")) { state.media.forEach(item => { if (item.status !== 'deleted') item.status = 'failed'; }); return { rows: [], rowCount: state.media.length }; }
    if (sql.includes("UPDATE account_deletion_jobs SET status = 'failed'")) { state.job = 'failed'; return { rows: [], rowCount: 1 }; }
    if (sql.includes("UPDATE account_deletion_jobs") && sql.includes("status = 'complete'")) { state.job = 'complete'; return { rows: [], rowCount: 1 }; }
    if (sql.includes("UPDATE account_deletion_jobs SET status = 'running'")) { state.job = 'running'; return { rows: [], rowCount: 1 }; }
    return { rows: [], rowCount: 1 };
  };
  const client = { query, release: () => undefined };
  return { pool: { connect: async () => client, query } as never, sqlLog };
}

test('account deletion captures only database-proven user-owned media and completes after exact-key cleanup', async () => {
  const state: State = { deleted: false, job: 'pending', media: [
    { key: `${userId}/avatar/2026-10-10/a.png`, status: 'pending' },
    { key: `${userId}/post/2026-10-10/p.mp4`, status: 'pending' }
  ] };
  const calls: string[][] = [];
  const media: MediaDeleter = { deleteObjects: async paths => { calls.push([...paths]); return { deleted: paths.length, requested: paths.length }; } };
  const removed: string[] = [];
  const { pool, sqlLog } = fakeDeletionPool(state);
  const service = new AccountDeletionService(pool, { deleteIdentity: async uid => { removed.push(uid); } }, undefined, media);
  assert.deepEqual(await service.deleteAccount(userId), { deleted: true });
  assert.deepEqual(calls, [[`${userId}/avatar/2026-10-10/a.png`, `${userId}/post/2026-10-10/p.mp4`]]);
  assert.deepEqual(removed, ['firebase-u1']);
  assert.equal(state.deleted, true);
  assert.equal(state.job, 'complete');
  assert.ok(sqlLog.some(sql => sql.includes('post_media')));
  assert.ok(sqlLog.some(sql => sql.includes('product_media')));
  assert.ok(sqlLog.some(sql => sql.includes('message_attachments')));
});

test('storage failure commits the tombstone but reports pending and a later retry completes cleanup', async () => {
  const state: State = { deleted: false, job: 'pending', media: [{ key: `${userId}/message/2026-10-10/m.wav`, status: 'pending' }] };
  let attempts = 0;
  const media: MediaDeleter = { deleteObjects: async paths => { attempts += 1; if (attempts === 1) throw new Error('temporary storage timeout'); return { deleted: paths.length, requested: paths.length }; } };
  const removed: string[] = [];
  const { pool } = fakeDeletionPool(state);
  const service = new AccountDeletionService(pool, { deleteIdentity: async uid => { removed.push(uid); } }, undefined, media);
  assert.deepEqual(await service.deleteAccount(userId), { deleted: true, cleanupPending: true });
  assert.equal(state.deleted, true);
  assert.deepEqual(await service.deleteAccount(userId), { deleted: true });
  assert.equal(attempts, 2);
  assert.deepEqual(removed, ['firebase-u1']);
  assert.equal(state.media[0]!.status, 'deleted');
});

test('incomplete provider result does not report full deletion or mark media complete', async () => {
  const state: State = { deleted: false, job: 'pending', media: [{ key: `${userId}/post/2026-10-10/p.png`, status: 'pending' }] };
  const media: MediaDeleter = { deleteObjects: async paths => ({ deleted: paths.length - 1, requested: paths.length }) };
  const { pool } = fakeDeletionPool(state);
  const service = new AccountDeletionService(pool, { deleteIdentity: async () => { throw new Error('must not run'); } }, undefined, media);
  assert.deepEqual(await service.deleteAccount(userId), { deleted: true, cleanupPending: true });
  assert.equal(state.media[0]!.status, 'failed');
  assert.equal(state.job, 'failed');
});
