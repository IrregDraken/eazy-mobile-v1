import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { createHomeRouter, createPostRouter } from '../src/modules/posts/routes.js';
import type { PostService } from '../src/modules/posts/service.js';

const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

const fakeService = {
  getById: async () => ({ id: '00000000-0000-0000-0000-000000000001', content: 'Public', visibility: 'public', author: { username: 'author_user', displayName: 'Author', avatarUrl: null }, media: [], likeCount: 0, commentCount: 0, saveCount: 0, likedByViewer: false, savedByViewer: false }),
  feed: async () => ({ items: [], meta: { page: 1, limit: 20, cursor: null, total: 0, pages: 0 } }),
  create: async () => { throw new Error('should not create without auth'); },
  delete: async () => { throw new Error('should not delete without auth'); }
} as unknown as PostService;

test('post creation, deletion, and home feed require authentication', async () => {
  const app = createApp(config, createLogger(config), { postRouter: createPostRouter(fakeService), homeRouter: createHomeRouter(fakeService) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const requests = [
      fetch(`http://127.0.0.1:${address.port}/v1/posts`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ content: 'x' }) }),
      fetch(`http://127.0.0.1:${address.port}/v1/posts/00000000-0000-0000-0000-000000000001`, { method: 'DELETE' }),
      fetch(`http://127.0.0.1:${address.port}/v1/home/feed`)
    ];
    for (const response of await Promise.all(requests)) {
      const body = await response.json();
      assert.equal(response.status, 401);
      assert.equal(body.error.code, 'UNAUTHORIZED');
    }
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

test('public post retrieval returns safe projection without authentication metadata', async () => {
  const app = createApp(config, createLogger(config), { postRouter: createPostRouter(fakeService) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/posts/00000000-0000-0000-0000-000000000001`);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.data.post.author.username, 'author_user');
    assert.equal('firebaseUid' in body.data.post, false);
    assert.equal('sessionId' in body.data.post, false);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
