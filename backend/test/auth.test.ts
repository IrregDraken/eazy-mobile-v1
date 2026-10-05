import assert from 'node:assert/strict';
import test from 'node:test';
import { FirebaseAuthProvider } from '../src/providers/firebase-auth.js';
import { loadConfig } from '../src/config/env.js';
import { AppError } from '../src/middleware/errors.js';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';

const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent' });

test('Firebase provider refuses to initialize without server credentials', () => {
  assert.throws(() => new FirebaseAuthProvider(config), (error: unknown) => error instanceof AppError && error.code === 'SERVICE_UNAVAILABLE');
});

test('auth endpoints do not provide fake authentication when Firebase is unavailable', async () => {
  const app = createApp(config, createLogger(config));
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    for (const path of ['/v1/auth/me', '/v1/auth/session', '/v1/auth/logout']) {
      const response: Response = await fetch(`http://127.0.0.1:${address.port}${path}`, { method: path.endsWith('logout') ? 'POST' : 'GET' });
      const body = await response.json();
      assert.equal(response.status, 503);
      assert.equal(body.success, false);
      assert.equal(body.error.code, 'SERVICE_UNAVAILABLE');
      assert.equal(body.requestId, response.headers.get('x-request-id'));
    }
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
