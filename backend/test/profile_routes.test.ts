import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { createProfileRouter } from '../src/modules/profiles/routes.js';
import { ProfileService } from '../src/modules/profiles/service.js';

const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

const fakeService = {
  getPublic: async (username: string) => ({ username, displayName: 'Public', firstName: null, lastName: null, bio: null, avatarUrl: null }),
  isUsernameAvailable: async (username: string) => ({ username, available: true }),
  getMe: async () => { throw new Error('should not be called without auth'); },
  update: async () => { throw new Error('should not be called without auth'); },
  completeOnboarding: async () => { throw new Error('should not be called without auth'); }
} as unknown as ProfileService;

test('profile routes require authentication for current-user operations', async () => {
  const app = createApp(config, createLogger(config), { profileRouter: createProfileRouter(fakeService) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/profiles/me`);
    const body = await response.json();
    assert.equal(response.status, 401);
    assert.equal(body.error.code, 'UNAUTHORIZED');
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

test('public profile and username availability routes return safe standardized data', async () => {
  const app = createApp(config, createLogger(config), { profileRouter: createProfileRouter(fakeService) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const profile = await fetch(`http://127.0.0.1:${address.port}/v1/profiles/public_user`);
    assert.equal(profile.status, 200);
    assert.deepEqual((await profile.json()).data.profile.username, 'public_user');
    const availability = await fetch(`http://127.0.0.1:${address.port}/v1/profiles/username/new_user/availability`);
    assert.equal(availability.status, 200);
    assert.equal((await availability.json()).data.available, true);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
