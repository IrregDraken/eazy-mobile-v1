import assert from 'node:assert/strict';
import test from 'node:test';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { AccountDeletionService } from '../src/modules/auth/account-deletion.js';
import { AppError } from '../src/middleware/errors.js';

const U = '00000000-0000-4000-8000-0000000000a1';
const OTHER = '00000000-0000-4000-8000-0000000000b2';

// ---------- unit tests (no database) ----------
function fakePool(handler: (sql: string, values?: unknown[]) => { rows?: unknown[]; rowCount?: number }) {
  const log: string[] = [];
  const client = {
    query: async (sql: string, values?: unknown[]) => {
      log.push(sql.trim().split(/\s+/).slice(0, 3).join(' '));
      const r = handler(sql, values); return { rows: r.rows ?? [], rowCount: r.rowCount ?? (r.rows?.length ?? 0) };
    },
    release: () => undefined
  };
  return { pool: { connect: async () => client, query: client.query } as never, log };
}

test('deleting an account that is already deleted is a harmless no-op', async () => {
  const { pool, log } = fakePool(sql => sql.includes('FOR UPDATE') && !sql.includes('account_deletion_jobs') ? { rows: [{ firebase_uid: 'f1', email: null, status: 'deleted' }] } : {});
  let removed = 0;
  const service = new AccountDeletionService(pool, { deleteIdentity: async () => { removed += 1; } });
  assert.deepEqual(await service.deleteAccount(U), { deleted: true });
  assert.equal(removed, 0);
  assert.ok(!log.some(entry => entry.startsWith('DELETE')));
});

test('a wallet balance blocks deletion with a clear message and nothing is changed', async () => {
  const { pool, log } = fakePool(sql => sql.includes('FOR UPDATE')
    ? { rows: [{ firebase_uid: 'f1', email: 'a@b.co', status: 'active' }] }
    : sql.includes('AS balance') ? { rows: [{ balance: '1500.00', pending: '0', orders: '0', sales: '0' }] } : {});
  const service = new AccountDeletionService(pool, { deleteIdentity: async () => { throw new Error('must not be called'); } });
  await assert.rejects(() => service.deleteAccount(U), (error: unknown) =>
    error instanceof AppError && error.code === 'CONFLICT' && /wallet/i.test(error.message));
  assert.ok(!log.some(entry => entry.startsWith('DELETE') || entry.startsWith('UPDATE')));
});

test('if the sign-in identity cannot be removed the deleted account remains blocked and cleanup is retryable', async () => {
  const { pool, log } = fakePool(sql => sql.includes('account_deletion_jobs')
    ? { rows: [{ firebase_uid: 'f1', identity_deleted: false, status: 'pending' }] }
    : sql.includes('FOR UPDATE')
    ? { rows: [{ firebase_uid: 'f1', email: 'a@b.co', status: 'active' }] }
    : sql.includes('AS balance') ? { rows: [{ balance: '0', pending: '0', orders: '0', sales: '0' }] } : {});
  const service = new AccountDeletionService(pool, { deleteIdentity: async () => { throw new AppError('SERVICE_UNAVAILABLE', 'Firebase unavailable'); } });
  assert.deepEqual(await service.deleteAccount(U), { deleted: true, cleanupPending: true });
  assert.ok(log.includes('COMMIT'), `expected committed database tombstone in ${log.join(' | ')}`);
});

// ---------- integration test against a real, fully migrated PostgreSQL (explicitly opt-in) ----------
// The test is intentionally limited to a disposable local PostgreSQL instance. The CI job sets all
// three safety variables and applies backend/migrations before running the suite.
const url = process.env.TEST_DATABASE_URL;
const runRealDatabaseTest = process.env.EAZY_RUN_INTEGRATION_TEST === 'true' || Boolean(url);
test('account deletion against a real database', { skip: runRealDatabaseTest ? false : 'set TEST_DATABASE_URL to run' }, async () => {
  assertSafeIntegrationDatabase(url);
  const pool = new pg.Pool({ connectionString: url });
  const q = (sql: string, values?: unknown[]) => pool.query(sql, values);
  // Use a THROWAWAY database. The ledger is append-only (a trigger rejects deletes) and a deleted account keeps a
  // tombstone row, so this test cannot clean up after itself; every run therefore uses fresh ids and unique values.
  const [lowId, highId] = [randomUUID(), randomUUID()].sort();
  const U = lowId; const OTHER = highId; const tag = randomUUID().replace(/-/g, '').slice(0, 12);
  try {
    await q(`INSERT INTO users (id, firebase_uid, email, phone) VALUES ($1,$3,$4,$5),($2,$6,$7,NULL)`, [U, OTHER, `fb-u-${tag}`, `person-${tag}@example.com`, `+234${tag.replace(/\D/g, '').padEnd(9, '7').slice(0, 9)}`, `fb-o-${tag}`, `other-${tag}@example.com`]);
    await q(`INSERT INTO profiles (user_id, username, display_name, bio, first_name, last_name, date_of_birth) VALUES ($1,$3,'Real Name','my bio','Real','Name','1990-01-01'),($2,$4,'Other','x',NULL,NULL,NULL)`, [U, OTHER, `p_${tag}`, `o_${tag}`]);
    const post = (await q(`INSERT INTO posts (author_id, content) VALUES ($1,'hello'),($2,'theirs') RETURNING id, author_id`, [U, OTHER])).rows;
    const otherPost = post.find(r => r.author_id === OTHER).id;
    await q('INSERT INTO likes (user_id, post_id) VALUES ($1,$2)', [U, otherPost]);
    await q('INSERT INTO comments (post_id, author_id, content) VALUES ($1,$2,$3)', [otherPost, U, 'nice']);
    await q('INSERT INTO follows (follower_id, followee_id) VALUES ($1,$2),($2,$1)', [U, OTHER]);
    const conv = (await q('INSERT INTO conversations (created_by, direct_user_low_id, direct_user_high_id) VALUES ($1,$1,$2) RETURNING id', [U, OTHER])).rows[0].id;
    await q('INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1,$2),($1,$3)', [conv, U, OTHER]);
    await q(`INSERT INTO messages (conversation_id, sender_id, body) VALUES ($1,$2,'secret words'),($1,$3,'reply')`, [conv, U, OTHER]);
    await q(`INSERT INTO products (seller_id, name, price_amount, currency, status) VALUES ($1,'Phone',100,'NGN','active')`, [U]);
    await q(`INSERT INTO push_devices (user_id, device_token, platform) VALUES ($1,$2,'android')`, [U, `tok-${tag}`]);
    await q(`INSERT INTO user_settings (user_id) VALUES ($1) ON CONFLICT DO NOTHING`, [U]);
    const wallet = (await q(`INSERT INTO wallets (user_id, currency) VALUES ($1,'NGN') RETURNING id`, [U])).rows[0].id;
    const tx = (await q(`INSERT INTO transactions (user_id, wallet_id, type, status, amount, currency, reference, idempotency_key) VALUES ($1,$2,'deposit','succeeded',500,'NGN',$3,$4) RETURNING id`, [U, wallet, `ref-${tag}`, `idem-${tag}`])).rows[0].id;
    await q(`INSERT INTO ledger_entries (wallet_id, transaction_id, direction, amount, currency, entry_type, idempotency_key) VALUES ($1,$2,'credit',500,'NGN','deposit',$3)`, [wallet, tx, `l1-${tag}`]);

    const removed: string[] = [];
    const service = new AccountDeletionService(pool, { deleteIdentity: async uid => { removed.push(uid); } });

    // 1) money in the wallet blocks deletion and changes nothing
    const pre = await service.preflight(U);
    assert.equal(pre.canDelete, false);
    assert.equal(pre.blockers[0]?.code, 'WALLET_BALANCE');
    await assert.rejects(() => service.deleteAccount(U), (e: unknown) => e instanceof AppError && e.code === 'CONFLICT');
    assert.equal((await q('SELECT status FROM users WHERE id=$1', [U])).rows[0].status, 'active');
    assert.deepEqual(removed, []);

    // 2) once the balance is withdrawn, deletion succeeds
    await q(`INSERT INTO ledger_entries (wallet_id, transaction_id, direction, amount, currency, entry_type, idempotency_key) VALUES ($1,$2,'debit',500,'NGN','withdrawal',$3)`, [wallet, tx, `l2-${tag}`]);
    assert.equal((await service.preflight(U)).canDelete, true);
    assert.deepEqual(await service.deleteAccount(U, { ipAddress: '127.0.0.1' }), { deleted: true });
    assert.deepEqual(removed, [`fb-u-${tag}`]);

    const user = (await q('SELECT status, email, phone FROM users WHERE id=$1', [U])).rows[0];
    assert.deepEqual(user, { status: 'deleted', email: null, phone: null });
    const profile = (await q('SELECT username, display_name, bio, first_name, last_name, date_of_birth, avatar_url FROM profiles WHERE user_id=$1', [U])).rows[0];
    assert.match(profile.username, /^deleted_[0-9a-f]{12}$/);
    assert.equal(profile.display_name, 'Deleted user');
    assert.equal(profile.bio, null); assert.equal(profile.first_name, null); assert.equal(profile.date_of_birth, null);

    for (const [table, col] of [['posts', 'author_id'], ['likes', 'user_id'], ['comments', 'author_id'], ['push_devices', 'user_id']] as const) {
      assert.equal(Number((await q(`SELECT count(*) FROM ${table} WHERE ${col}=$1`, [U])).rows[0].count), 0, `${table} should be empty`);
    }
    assert.equal(Number((await q('SELECT count(*) FROM conversation_members WHERE user_id=$1 AND left_at IS NULL', [U])).rows[0].count), 0);
    assert.equal(Number((await q('SELECT count(*) FROM follows WHERE follower_id=$1 OR followee_id=$1', [U])).rows[0].count), 0);
    // the other person's content and thread survive; the deleted person's words do not
    assert.equal(Number((await q('SELECT count(*) FROM posts WHERE id=$1', [otherPost])).rows[0].count), 1);
    const msgs = (await q('SELECT sender_id, body, status FROM messages WHERE conversation_id=$1 ORDER BY created_at', [conv])).rows;
    assert.equal(msgs.find(m => m.sender_id === U).body, null);
    assert.equal(msgs.find(m => m.sender_id === U).status, 'deleted');
    assert.equal(msgs.find(m => m.sender_id === OTHER).body, 'reply');
    assert.equal((await q(`SELECT status FROM products WHERE seller_id=$1`, [U])).rows[0].status, 'archived');
    // financial records are retained
    assert.equal(Number((await q('SELECT count(*) FROM transactions WHERE user_id=$1', [U])).rows[0].count), 1);
    assert.equal(Number((await q('SELECT count(*) FROM ledger_entries WHERE wallet_id=$1', [wallet])).rows[0].count), 2);
    assert.equal((await q('SELECT status FROM wallets WHERE id=$1', [wallet])).rows[0].status, 'closed');
    assert.equal(Number((await q(`SELECT count(*) FROM security_events WHERE user_id=$1 AND event_type='account_deleted'`, [U])).rows[0].count), 1);

    // 3) calling it again is idempotent
    assert.deepEqual(await service.deleteAccount(U), { deleted: true });
    assert.deepEqual(removed, [`fb-u-${tag}`]);
  } finally {
    await pool.end();
  }
});

function assertSafeIntegrationDatabase(rawUrl: string | undefined): asserts rawUrl is string {
  if (!rawUrl) throw new Error('TEST_DATABASE_URL is required when the real integration test is enabled');
  if (process.env.EAZY_TEST_DATABASE_CONFIRMED !== 'true') {
    throw new Error('EAZY_TEST_DATABASE_CONFIRMED=true is required for the destructive integration test');
  }
  const parsed = new URL(rawUrl);
  if (!['postgres:', 'postgresql:'].includes(parsed.protocol)) {
    throw new Error('TEST_DATABASE_URL must use the PostgreSQL protocol');
  }
  if (!['127.0.0.1', 'localhost', '::1'].includes(parsed.hostname.toLowerCase())) {
    throw new Error('TEST_DATABASE_URL must point to a local disposable PostgreSQL instance');
  }
  const expectedDatabase = process.env.EAZY_TEST_DATABASE_NAME;
  const actualDatabase = decodeURIComponent(parsed.pathname.replace(/^\//, ''));
  if (!expectedDatabase || actualDatabase !== expectedDatabase) {
    throw new Error('TEST_DATABASE_URL does not match the explicitly configured isolated test database');
  }
}
