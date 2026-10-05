import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { createSocialRouter } from '../src/modules/social/routes.js';
import type { SocialService } from '../src/modules/social/service.js';

const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

const fakeService = {
  list: async (_userId: string | undefined, _direction: string, _username: string, pagination: { limit: number }) => ({ items: [], meta: { page: 1, limit: pagination.limit, cursor: null, total: 0, pages: 0 } })
} as unknown as SocialService;

test('social mutations and relationship state require authentication', async () => {
  const app = createApp(config, createLogger(config), { socialRouter: createSocialRouter(fakeService) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    for (const [path, method] of [['/v1/social/follow/other_user', 'POST'], ['/v1/social/relationship/other_user', 'GET'], ['/v1/social/users/search?q=other', 'GET']] as const) {
      const response: Response = await fetch(`http://127.0.0.1:${address.port}${path}`, { method });
      const body = await response.json();
      assert.equal(response.status, 401);
      assert.equal(body.error.code, 'UNAUTHORIZED');
    }
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

test('follower list route uses bounded pagination and standardized response', async () => {
  const app = createApp(config, createLogger(config), { socialRouter: createSocialRouter(fakeService) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/social/followers/other_user?page=1&limit=50`);
    assert.equal(response.status, 200);
    const body = await response.json();
    assert.equal(body.success, true);
    assert.equal(body.data.meta.limit, 50);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
