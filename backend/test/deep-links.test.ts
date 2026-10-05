import assert from 'node:assert/strict';
import test from 'node:test';
import type { RequestHandler } from 'express';
import type { Pool } from 'pg';
import { AppError } from '../src/middleware/errors.js';
import { DeepLinkService, parseDeepLink, type DeepLinkServices } from '../src/modules/deep-links/service.js';
import { createDeepLinkRouter } from '../src/modules/deep-links/routes.js';
import type { SocialRepository } from '../src/modules/social/repository.js';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';

const resourceId = '10000000-0000-4000-8000-000000000001';
const ownId = '20000000-0000-4000-8000-000000000001';

function harness() {
  const calls: string[] = [];
  const services: DeepLinkServices = {
    profiles: { getPublic: async username => { calls.push(`profile:${username}`); return { username, displayName: 'Alice', firstName: null, lastName: null, bio: null, avatarUrl: null }; } },
    posts: { getById: async (id, viewer) => { calls.push(`post:${id}:${viewer ?? 'anonymous'}`); return { id } as never; } },
    marketplace: { detail: async (id, viewer) => { calls.push(`product:${id}:${viewer ?? 'anonymous'}`); return { product: { id } } as never; } },
    orders: { get: async (viewer, id) => { calls.push(`order:${viewer}:${id}`); if (viewer === 'not-owner') throw new AppError('NOT_FOUND', 'Order not found'); return { order: {} } as never; } },
    notifications: { get: async (viewer, id) => { calls.push(`notification:${viewer}:${id}`); return { notification: {} } as never; } },
    chat: { getConversation: async (viewer, id) => { calls.push(`chat:${viewer}:${id}`); return { conversation: {} } as never; } }
  };
  const social = {
    targetByUsername: async (_pool: unknown, username: string) => username === 'alice_1' ? { id: ownId, username } : null,
    isBlocked: async (_pool: unknown, viewer: string) => viewer === 'blocked-viewer'
  } as unknown as SocialRepository;
  return { calls, service: new DeepLinkService(services, {} as Pool, social) };
}

function expectError(operation: () => unknown, code: AppError['code']) {
  assert.throws(operation, (error: unknown) => error instanceof AppError && error.code === code);
}

async function expectReject(operation: () => Promise<unknown>, code: AppError['code']) {
  await assert.rejects(operation, (error: unknown) => error instanceof AppError && error.code === code);
}

test('deep-link parser normalizes canonical paths, full URLs, usernames, trailing slashes, and duplicate separators', () => {
  assert.deepEqual(parseDeepLink('/u/ALICE_1/'), { type: 'profile', identifier: 'alice_1' });
  assert.deepEqual(parseDeepLink('https://eazy.app/p//10000000-0000-4000-8000-000000000001/'), { type: 'post', id: resourceId });
  assert.deepEqual(parseDeepLink(`/product/${resourceId.toUpperCase()}`), { type: 'product', id: resourceId });
  assert.deepEqual(parseDeepLink(`/order/${resourceId}`), { type: 'order', id: resourceId });
  assert.deepEqual(parseDeepLink(`/notification/${resourceId}`), { type: 'notification', id: resourceId });
  assert.deepEqual(parseDeepLink(`/chat/${resourceId}`), { type: 'conversation', id: resourceId });
});

test('deep-link parser rejects malformed links, schemes, hosts, queries, path traversal, separators, and IDs', () => {
  for (const input of [
    'http://eazy.app/p/' + resourceId,
    'javascript:alert(1)',
    'https://evil.example/p/' + resourceId,
    'https://eazy.app.evil.example/p/' + resourceId,
    '//eazy.app/p/' + resourceId,
    '/p/' + resourceId + '?redirect=https://evil.example',
    '/p/' + resourceId + '#fragment',
    '/../p/' + resourceId,
    '/%2e%2e/p/' + resourceId,
    '/p%2f' + resourceId,
    '/p/not-a-uuid',
    '/wallet/' + resourceId,
    'https://user@eazy.app/p/' + resourceId
  ]) expectError(() => parseDeepLink(input), input.includes('wallet') ? 'NOT_FOUND' : 'VALIDATION_ERROR');
});

test('public resource resolution delegates to existing profile, post, and marketplace authorization and returns only navigation data', async () => {
  const { calls, service } = harness();
  const profile = await service.resolve('/u/alice_1');
  assert.deepEqual(profile, { type: 'profile', identifier: 'alice_1', destination: '/u/alice_1' });
  const post = await service.resolve(`/p/${resourceId}`);
  assert.deepEqual(post, { type: 'post', id: resourceId, destination: `/p/${resourceId}` });
  const product = await service.resolve(`/product/${resourceId}`);
  assert.deepEqual(product, { type: 'product', id: resourceId, destination: `/product/${resourceId}` });
  assert.deepEqual(calls, [`profile:alice_1`, `post:${resourceId}:anonymous`, `product:${resourceId}:anonymous`]);
  assert.equal('content' in post, false);
  assert.equal('priceAmount' in product, false);
});

test('profile resolution hides missing, inactive, and blocked targets', async () => {
  const { service } = harness();
  await expectReject(() => service.resolve('/u/unknown_1'), 'NOT_FOUND');
  await expectReject(() => service.resolve('/u/alice_1', 'blocked-viewer'), 'NOT_FOUND');
});

test('private order, notification, and conversation targets require authentication and delegate ownership checks', async () => {
  const { calls, service } = harness();
  await expectReject(() => service.resolve(`/order/${resourceId}`), 'UNAUTHORIZED');
  await expectReject(() => service.resolve(`/notification/${resourceId}`), 'UNAUTHORIZED');
  await expectReject(() => service.resolve(`/chat/${resourceId}`), 'UNAUTHORIZED');
  for (const path of [`/order/${resourceId}`, `/notification/${resourceId}`, `/chat/${resourceId}`]) {
    const result = await service.resolve(path, 'viewer-id');
    assert.equal(result.destination, path);
  }
  assert.deepEqual(calls, [`order:viewer-id:${resourceId}`, `notification:viewer-id:${resourceId}`, `chat:viewer-id:${resourceId}`]);
});

test('domain not-found results prevent cross-user and nonexistent private resource disclosure', async () => {
  const { service } = harness();
  await expectReject(() => service.resolve(`/order/${resourceId}`, 'not-owner'), 'NOT_FOUND');
});

test('all supported routes return stable canonical Eazy destinations without arbitrary redirect handling', async () => {
  const { service } = harness();
  const expected = [
    ['/u/alice_1', '/u/alice_1'],
    [`/p/${resourceId}`, `/p/${resourceId}`],
    [`/product/${resourceId}`, `/product/${resourceId}`],
    [`/order/${resourceId}`, `/order/${resourceId}`],
    [`/notification/${resourceId}`, `/notification/${resourceId}`],
    [`/chat/${resourceId}`, `/chat/${resourceId}`]
  ] as const;
  for (const [path, destination] of expected) {
    const result = await service.resolve(path, 'viewer-id');
    assert.equal(result.destination, destination);
  }
});

test('HTTP resolution accepts public targets, rejects unknown query parameters, and authenticates private targets', async () => {
  const { service } = harness();
  const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;
  const auth: RequestHandler = (request, _response, next) => {
    if (request.header('authorization') === 'Bearer test-token') request.auth = { userId: 'viewer-id', provider: 'test', claims: {} };
    next();
  };
  const app = createApp(config, createLogger(config), { authMiddleware: auth, deepLinkRouter: createDeepLinkRouter(service) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const baseUrl = `http://127.0.0.1:${address.port}/v1/deep-links/resolve`;
    const publicResult = await fetch(`${baseUrl}?path=${encodeURIComponent(`/p/${resourceId}`)}`);
    assert.equal(publicResult.status, 200);
    assert.deepEqual((await publicResult.json()).data, { type: 'post', id: resourceId, destination: `/p/${resourceId}` });
    const unknownQuery = await fetch(`${baseUrl}?path=${encodeURIComponent(`/p/${resourceId}`)}&redirect=https%3A%2F%2Fevil.example`);
    assert.equal(unknownQuery.status, 422);
    const externalTarget = await fetch(`${baseUrl}?path=${encodeURIComponent(`https://evil.example/p/${resourceId}`)}`);
    assert.equal(externalTarget.status, 422);
    const privateAnonymous = await fetch(`${baseUrl}?path=${encodeURIComponent(`/order/${resourceId}`)}`);
    assert.equal(privateAnonymous.status, 401);
    const privateOwned = await fetch(`${baseUrl}?path=${encodeURIComponent(`/order/${resourceId}`)}`, { headers: { authorization: 'Bearer test-token' } });
    assert.equal(privateOwned.status, 200);
    const privateData = await privateOwned.json();
    assert.deepEqual(privateData.data, { type: 'order', id: resourceId, destination: `/order/${resourceId}` });
    assert.equal('order' in privateData.data, false);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
