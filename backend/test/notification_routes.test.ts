import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { createNotificationRouter } from '../src/modules/notifications/routes.js';
import type { NotificationService } from '../src/modules/notifications/service.js';

const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

test('notification API requires authentication and has no public create endpoint', async () => {
  const app = createApp(config, createLogger(config), { notificationRouter: createNotificationRouter({} as NotificationService) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const list = await fetch(`http://127.0.0.1:${address.port}/v1/notifications`);
    assert.equal(list.status, 401);
    const create = await fetch(`http://127.0.0.1:${address.port}/v1/notifications`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ recipientUserId: '00000000-0000-0000-0000-000000000001', type: 'system' }) });
    assert.equal(create.status, 404);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
