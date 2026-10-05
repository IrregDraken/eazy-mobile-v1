import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../src/config/env.js';
import { AppError } from '../src/middleware/errors.js';
import { AuthService } from '../src/modules/auth/service.js';
import { SettingsRepository } from '../src/modules/settings/repository.js';
import { SettingsService } from '../src/modules/settings/service.js';
import { settingsPatchSchema } from '../src/modules/settings/schemas.js';
import { projectUserSettings } from '../src/modules/settings/types.js';
import { createSettingsRouter } from '../src/modules/settings/routes.js';
import { createBlockRouter } from '../src/modules/blocks/routes.js';
import { SocialService } from '../src/modules/social/service.js';
import { ProfileRepository } from '../src/modules/profiles/repository.js';
import { NotificationRepository } from '../src/modules/notifications/repository.js';
import { NotificationService } from '../src/modules/notifications/service.js';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import type { AuthContext } from '../src/middleware/auth.js';
import { createAuthRouter, createFirebaseAuthenticationMiddleware } from '../src/modules/auth/routes.js';
import { RealtimeService } from '../src/modules/realtime/service.js';

const userA = '00000000-0000-4000-8000-000000000001';
const userB = '00000000-0000-4000-8000-000000000002';
const sessionId = '10000000-0000-4000-8000-000000000001';
const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent', EAZY_SESSION_TTL_DAYS: '30' });

function fakePool(client: { query: (sql: string, values?: unknown[]) => Promise<{ rows?: unknown[]; rowCount?: number | null }>; release?: () => void }) {
  return { connect: async () => ({ ...client, release: client.release ?? (() => undefined) }), query: client.query } as never;
}

function authFixture() {
  const sessions = new Map<string, { id: string; user_id: string; provider_session_id: string; expires_at: string; created_at: string; revoked_at: string | null }>();
  const profiles = new Map<string, { user_id: string; username: string; display_name: string }>();
  const security: Array<{ event: string; metadata: string }> = [];
  const pool = fakePool({
    async query(sql: string, values: unknown[] = []) {
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return { rows: [], rowCount: 0 };
      if (sql.includes('INSERT INTO users')) return { rows: [{ id: userA, firebase_uid: 'firebase-a', email: null, phone: null, status: 'active' }], rowCount: 1 };
      if (sql.includes('SELECT user_id, username, display_name FROM profiles')) return { rows: profiles.has(userA) ? [profiles.get(userA)] : [], rowCount: profiles.has(userA) ? 1 : 0 };
      if (sql.includes('INSERT INTO profiles')) {
        const row = { user_id: userA, username: 'user_firebasea', display_name: 'A' };
        profiles.set(userA, row);
        return { rows: [row], rowCount: 1 };
      }
      if (sql.includes('INSERT INTO sessions')) {
        const [owner, providerId] = values as [string, string];
        if ([...sessions.values()].some(row => row.user_id === owner && row.provider_session_id === providerId)) return { rows: [], rowCount: 0 };
        const row = { id: sessionId, user_id: owner, provider_session_id: providerId, expires_at: new Date(Date.now() + 86_400_000).toISOString(), created_at: new Date().toISOString(), revoked_at: null };
        sessions.set(sessionId, row);
        return { rows: [{ id: sessionId }], rowCount: 1 };
      }
      if (sql.includes('SELECT id, expires_at, created_at FROM sessions')) {
        const owner = String(values[0]);
        const providerId = String(values[1]);
        const row = [...sessions.values()].find(item => item.user_id === owner && item.provider_session_id === providerId);
        return { rows: row ? [{ id: row.id, expires_at: row.expires_at, created_at: row.created_at }] : [], rowCount: row ? 1 : 0 };
      }
      if (sql.includes('UPDATE sessions SET last_activity_at')) {
        const row = sessions.get(String(values[0]));
        if (!row || row.revoked_at || new Date(row.expires_at).getTime() <= Date.now()) return { rows: [], rowCount: 0 };
        return { rows: [{ revoked_at: null, expires_at: row.expires_at }], rowCount: 1 };
      }
      if (sql.includes('UPDATE sessions SET revoked_at = now() WHERE id')) {
        const row = sessions.get(String(values[0]));
        if (!row || row.user_id !== values[1] || row.revoked_at) return { rows: [], rowCount: 0 };
        row.revoked_at = new Date().toISOString();
        return { rows: [{ id: row.id }], rowCount: 1 };
      }
      if (sql.includes('UPDATE sessions SET revoked_at = now() WHERE user_id')) {
        const owner = String(values[0]);
        const rows = [...sessions.values()].filter(row => row.user_id === owner && !row.revoked_at);
        for (const row of rows) row.revoked_at = new Date().toISOString();
        return { rows: rows.map(row => ({ id: row.id })), rowCount: rows.length };
      }
      if (sql.includes('INSERT INTO security_events')) {
        security.push({ event: String(values[1] ?? 'session_created'), metadata: String(values[values.length - 1]) });
        return { rows: [], rowCount: 1 };
      }
      if (sql.includes('SELECT id, created_at, last_activity_at')) return { rows: [...sessions.values()].filter(row => row.user_id === values[0]).map(row => ({ ...row, last_activity_at: row.created_at, ip_address: '127.0.0.1', user_agent: 'test-agent' })), rowCount: sessions.size };
      throw new Error(`Unexpected SQL: ${sql}`);
    }
  });
  return { pool, sessions, security, service: new AuthService(pool, config) };
}

function identity(authTime = 1_760_000_000) {
  return { firebaseUid: 'firebase-a', claims: { auth_time: authTime, email: 'private@example.test' } };
}

test('settings schema is strict, typed, canonicalizes BCP-47, and rejects unimplemented privacy/security controls', () => {
  assert.deepEqual(settingsPatchSchema.parse({ languageCode: 'fr-ca', theme: 'dark', notifications: { follows: false } }), {
    languageCode: 'fr-CA', theme: 'dark', notifications: { follows: false }
  });
  assert.throws(() => settingsPatchSchema.parse({ languageCode: 'not a language' }));
  assert.throws(() => settingsPatchSchema.parse({ userId: userB, theme: 'dark' }));
  assert.throws(() => settingsPatchSchema.parse({ privacy: { profileVisibility: 'private' } }));
  assert.throws(() => settingsPatchSchema.parse({ notifications: { orders: false } }));
  assert.deepEqual(projectUserSettings({ language_code: 'en', theme: 'system', notify_follows: true, notify_likes: false, notify_comments: true }), {
    languageCode: 'en', theme: 'system', notifications: { follows: true, likes: false, comments: true }
  });
});

test('Firebase auth_time maps repeated ID tokens to one Eazy session and revoked/expired sessions remain rejected', async () => {
  const state = authFixture();
  const first = await state.service.provision(identity());
  const refreshedToken = await state.service.provision(identity());
  assert.equal(first.context.sessionId, sessionId);
  assert.equal(refreshedToken.context.sessionId, sessionId);
  assert.equal(state.sessions.size, 1);
  assert.equal(state.security.filter(event => event.event === 'session_created').length, 1);
  const list = await state.service.listSessions(userA, sessionId);
  assert.equal(list.sessions[0]?.current, true);
  assert.equal(list.sessions[0]?.status, 'active');
  assert.equal('token_hash' in (list.sessions[0] ?? {}), false);
  assert.equal('provider_session_id' in (list.sessions[0] ?? {}), false);
  await state.service.revokeSession(userA, sessionId);
  await assert.rejects(() => state.service.provision(identity()), (error: unknown) => error instanceof AppError && error.code === 'UNAUTHORIZED');
  await assert.rejects(() => state.service.revokeSession(userB, sessionId), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
  assert.equal(state.security.some(event => event.event === 'session_revoked' && !event.metadata.includes('private@example.test')), true);
  const expired = authFixture();
  await expired.service.provision(identity());
  const expiredRow = expired.sessions.get(sessionId)!;
  expiredRow.expires_at = new Date(Date.now() - 1_000).toISOString();
  await assert.rejects(() => expired.service.provision(identity()), (error: unknown) => error instanceof AppError && error.code === 'UNAUTHORIZED');
});

test('a revoked Eazy session is rejected on the next HTTP request even while Firebase token verification succeeds', async () => {
  const state = authFixture();
  const provider = { verifyIdentity: async () => identity() } as never;
  const app = createApp(config, createLogger(config), {
    authMiddleware: createFirebaseAuthenticationMiddleware(provider, state.service),
    authRouter: createAuthRouter(state.service)
  });
  const server = app.listen(0);
  try {
    const address = server.address(); assert.ok(address && typeof address !== 'string');
    const endpoint = `http://127.0.0.1:${address.port}/v1/auth/session`;
    const first = await fetch(endpoint, { headers: { authorization: 'Bearer verified-firebase-token' } });
    assert.equal(first.status, 200);
    await state.service.revokeSession(userA, sessionId);
    const revoked = await fetch(endpoint, { headers: { authorization: 'Bearer verified-firebase-token' } });
    assert.equal(revoked.status, 401);
    assert.equal((await revoked.json()).error.code, 'UNAUTHORIZED');
  } finally { await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
});

test('revoke-all deliberately includes current session and terminates backend sessions', async () => {
  const state = authFixture();
  await state.service.provision(identity());
  const result = await state.service.revokeAllSessions(userA, sessionId);
  assert.deepEqual(result, { revoked: 1, currentSessionRevoked: true });
  await assert.rejects(() => state.service.provision(identity()), (error: unknown) => error instanceof AppError && error.code === 'UNAUTHORIZED');
  assert.equal(state.security.some(event => event.event === 'sessions_revoked_all'), true);
});

test('realtime session termination closes only sockets attached to the revoked Eazy session', () => {
  const closed: unknown[] = [];
  const sockets = [
    { readyState: 1, close: (...args: unknown[]) => closed.push(args), terminate: () => undefined },
    { readyState: 1, close: (...args: unknown[]) => closed.push(args), terminate: () => undefined }
  ];
  const realtime = new RealtimeService({} as never, {} as never, {} as never);
  assert.ok(realtime.register(sockets[0] as never, userA, sessionId));
  assert.ok(realtime.register(sockets[1] as never, userA, 'another-session'));
  realtime.terminateSession(userA, sessionId);
  assert.equal(realtime.dispatcher.getConnectionCountForUser(userA), 1);
  assert.equal(closed.length, 1);
  assert.deepEqual(closed[0], [1008, 'Session revoked']);
  realtime.terminateUserSessions(userA);
  assert.equal(realtime.dispatcher.getConnectionCountForUser(userA), 0);
  assert.equal(closed.length, 2);
});

test('settings are isolated to AuthContext identity and forged owner fields fail validation', async () => {
  const calls: Array<{ owner: string; patch?: unknown }> = [];
  const service = {
    get: async (owner: string) => { calls.push({ owner }); return { settings: { languageCode: 'en' } }; },
    update: async (owner: string, patch: unknown) => { calls.push({ owner, patch }); return { settings: { languageCode: 'fr' } }; }
  } as unknown as SettingsService;
  const auth: AuthContext = { userId: userA, provider: 'firebase', claims: {}, sessionId };
  const app = createApp(config, createLogger(config), {
    settingsRouter: createSettingsRouter(service),
    authMiddleware: (request, _response, next) => { request.auth = auth; next(); }
  });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}/v1/settings`;
    const get = await fetch(base);
    assert.equal(get.status, 200);
    assert.equal(calls[0]?.owner, userA);
    const patch = await fetch(base, { method: 'PATCH', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ theme: 'dark', userId: userB }) });
    assert.equal(patch.status, 422);
    assert.equal(calls.length, 1);
  } finally { await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
});

test('settings repository only writes explicit typed columns and never records preference values in security metadata', async () => {
  const sql: string[] = [];
  const client = {
    async query(query: string, values: unknown[] = []) {
      sql.push(query);
      if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(query)) return { rows: [], rowCount: 0 };
      if (query.startsWith('SELECT language_code')) return { rows: [{ language_code: 'en', theme: 'system', notify_follows: true, notify_likes: true, notify_comments: true }], rowCount: 1 };
      if (query.startsWith('UPDATE user_settings')) return { rows: [{ language_code: 'fr', theme: 'dark', notify_follows: false, notify_likes: true, notify_comments: true }], rowCount: 1 };
      if (query.includes('INSERT INTO security_events')) { assert.deepEqual(JSON.parse(String(values[1])), { changed: ['language_code', 'theme', 'notify_follows'] }); return { rows: [], rowCount: 1 }; }
      return { rows: [], rowCount: 0 };
    }
  };
  const repo = new SettingsRepository(fakePool(client));
  const result = await repo.update(userA, { languageCode: 'fr', theme: 'dark', notifications: { follows: false } });
  assert.deepEqual(result, { languageCode: 'fr', theme: 'dark', notifications: { follows: false, likes: true, comments: true } });
  assert.match(sql.find(query => query.startsWith('SELECT language_code')) ?? '', /WHERE user_id = \$1 LIMIT 1 FOR UPDATE/);
  assert.match(sql.find(query => query.startsWith('UPDATE user_settings')) ?? '', /WHERE user_id = \$1 RETURNING/);
  assert.equal(sql.some(query => query.includes('firebase_uid') || query.includes('token_hash')), false);
});

test('block API derives actor from AuthContext and rejects self/invalid targets', async () => {
  let owner: string | undefined;
  let target: string | undefined;
  const social = {
    listBlocks: async (id: string) => { owner = id; return { items: [], meta: {} }; },
    blockUser: async (id: string, targetId: string) => { owner = id; target = targetId; return { blocked: true, created: true }; },
    unblockUser: async (id: string, targetId: string) => { owner = id; target = targetId; return { blocked: false, removed: true }; }
  } as unknown as SocialService;
  const app = createApp(config, createLogger(config), {
    blockRouter: createBlockRouter(social),
    authMiddleware: (request, _response, next) => { request.auth = { userId: userA, provider: 'firebase', claims: {} }; next(); }
  });
  const server = app.listen(0);
  try {
    const address = server.address(); assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}/v1/blocks`;
    const create = await fetch(base, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ userId: userB, ownerId: userB }) });
    assert.equal(create.status, 422);
    const valid = await fetch(base, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ userId: userB }) });
    assert.equal(valid.status, 200);
    assert.equal(owner, userA); assert.equal(target, userB);
  } finally { await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
});

test('block-by-ID service rejects self and missing/inactive users and treats duplicates safely', async () => {
  const pool = fakePool({ async query(sql: string) { if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(sql)) return { rows: [], rowCount: 0 }; throw new Error('unexpected query'); } });
  let insertCount = 0;
  const repository = {
    targetById: async (_client: unknown, id: string) => id === userB ? { id: userB, username: 'user_b' } : null,
    block: async () => { insertCount += 1; return insertCount === 1; },
    unblock: async () => true
  } as never;
  const social = new SocialService(pool, repository);
  assert.deepEqual(await social.blockUser(userA, userB), { blocked: true, created: true, user: { username: 'user_b' } });
  assert.deepEqual(await social.blockUser(userA, userB), { blocked: true, created: false, user: { username: 'user_b' } });
  await assert.rejects(() => social.blockUser(userA, userA), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
  const selfSocial = new SocialService(pool, { targetById: async () => ({ id: userA, username: 'self' }), block: async () => true } as never);
  await assert.rejects(() => selfSocial.blockUser(userA, userA), (error: unknown) => error instanceof AppError && error.code === 'BAD_REQUEST');
});

test('public profile repository hides reciprocal blocks for authenticated viewers but preserves anonymous lookup', async () => {
  const calls: unknown[][] = [];
  const statements: string[] = [];
  const repo = new ProfileRepository({ query: async (sql: string, values: unknown[]) => { statements.push(sql); calls.push(values); return { rows: [], rowCount: 0 }; } } as never);
  await repo.getPublicByUsername('user_b', userA);
  await repo.getPublicByUsername('user_b');
  assert.match(statements[0] ?? '', /FROM blocks/);
  assert.deepEqual(calls.map(call => call[1]), [userA, null]);
});

test('notification repository suppresses actor-recipient pairs blocked either direction or opted out', async () => {
  const queries: string[] = [];
  const client = {
    async query(sql: string) {
      queries.push(sql);
      if (sql.includes('SELECT\n         CASE')) return { rows: [{ enabled: false }], rowCount: 1 };
      return { rows: [{ id: 'notification-id' }], rowCount: 1 };
    }
  };
  const repository = new NotificationRepository({} as never);
  const result = await repository.create(client as never, { recipientUserId: userB, actorUserId: userA, type: 'follow' });
  assert.equal(result, null);
  assert.equal(queries.some(sql => sql.includes('INSERT INTO notifications')), false);
  assert.match(queries[0] ?? '', /notify_follows/);
  assert.match(queries[0] ?? '', /FROM blocks/);
});

test('push device token ownership is checked and no token is returned by registration', async () => {
  const pool = {
    query: async (sql: string) => {
      if (sql.includes('SELECT id, user_id FROM push_devices')) return { rows: [{ id: 'device-id', user_id: userB }], rowCount: 1 };
      throw new Error('registration must stop at ownership check');
    }
  } as never;
  const service = new NotificationService(pool);
  await assert.rejects(() => service.registerDevice(userA, { token: 'device-token-123456', platform: 'web' }),
    (error: unknown) => error instanceof AppError && error.code === 'FORBIDDEN');
  const owned = new NotificationService({ query: async (sql: string) => {
    if (sql.includes('SELECT id, user_id FROM push_devices')) return { rows: [], rowCount: 0 };
    if (sql.includes('INSERT INTO push_devices')) return { rows: [{ id: 'device-id' }], rowCount: 1 };
    throw new Error('unexpected query');
  } } as never);
  const result = await owned.registerDevice(userA, { token: 'device-token-123456', platform: 'web' });
  assert.deepEqual(result, { deviceId: 'device-id', pushDelivery: 'unavailable' });
  assert.equal(JSON.stringify(result).includes('device-token-123456'), false);
});

test('settings reject requests without AuthContext and deferred verification, lifecycle, and security-event endpoints stay unavailable', async () => {
  const service = { get: async () => ({ settings: {} }), update: async () => ({ settings: {} }) } as never;
  const state = authFixture();
  const app = createApp(config, createLogger(config), {
    settingsRouter: createSettingsRouter(service),
    authRouter: createAuthRouter(state.service),
    authMiddleware: (_request, _response, next) => next()
  });
  const server = app.listen(0);
  try {
    const address = server.address(); assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}`;
    const settings = await fetch(`${base}/v1/settings`);
    assert.equal(settings.status, 401);
    for (const [method, path] of [
      ['POST', '/v1/auth/verification-codes'],
      ['POST', '/v1/auth/account/deactivate'],
      ['POST', '/v1/auth/account/delete'],
      ['GET', '/v1/security-events'],
      ['PATCH', '/v1/security-events']
    ] as const) {
      const response = await fetch(`${base}${path}`, { method });
      assert.equal(response.status, 404, `${method} ${path} must remain unimplemented`);
    }
  } finally { await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
});

test('canonical block list and removal routes remain scoped to the authenticated owner', async () => {
  const calls: Array<{ action: string; owner: string; target?: string }> = [];
  const social = {
    listBlocks: async (owner: string) => { calls.push({ action: 'list', owner }); return { items: [], meta: {} }; },
    blockUser: async (owner: string, target: string) => { calls.push({ action: 'block', owner, target }); return { blocked: true, created: true }; },
    unblockUser: async (owner: string, target: string) => { calls.push({ action: 'unblock', owner, target }); return { blocked: false, removed: true }; }
  } as unknown as SocialService;
  const app = createApp(config, createLogger(config), {
    blockRouter: createBlockRouter(social),
    authMiddleware: (request, _response, next) => { request.auth = { userId: userA, provider: 'firebase', claims: {} }; next(); }
  });
  const server = app.listen(0);
  try {
    const address = server.address(); assert.ok(address && typeof address !== 'string');
    const base = `http://127.0.0.1:${address.port}/v1/blocks`;
    assert.equal((await fetch(base)).status, 200);
    assert.equal((await fetch(`${base}/${userB}`, { method: 'DELETE' })).status, 200);
    assert.deepEqual(calls, [
      { action: 'list', owner: userA },
      { action: 'unblock', owner: userA, target: userB }
    ]);
  } finally { await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())); }
});
