import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config/env.js';
import { createLogger } from '../src/config/logger.js';
import { normalizeRequestId } from '../src/middleware/request-id.js';
import { redactSensitive, REDACTED_VALUE } from '../src/config/redaction.js';

const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent', CORS_ORIGIN: '*', RATE_LIMIT_MAX: '50' });

async function withServer(app: ReturnType<typeof createApp>, run: (baseUrl: string) => Promise<void>) {
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
}

test('request IDs accept bounded safe values and replace malformed values', () => {
  assert.equal(normalizeRequestId('client.trace-01'), 'client.trace-01');
  assert.notEqual(normalizeRequestId('x'.repeat(129)), 'x'.repeat(129));
  assert.notEqual(normalizeRequestId('Bearer secret-token'), 'Bearer secret-token');
});

test('central redaction removes secrets recursively without changing safe metadata', () => {
  assert.deepEqual(redactSensitive({ userId: 'user-a', authorization: 'Bearer secret', nested: { pin: '1234' } }), {
    userId: 'user-a', authorization: REDACTED_VALUE, nested: { pin: REDACTED_VALUE }
  });
});

test('readiness is dependency-aware and returns a safe 503 response', async () => {
  const logger = createLogger(config);
  const app = createApp(config, logger, { readinessCheck: async () => false });
  await withServer(app, async baseUrl => {
    const response = await fetch(`${baseUrl}/ready`);
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), {
      success: false,
      error: { code: 'SERVICE_UNAVAILABLE', message: 'Service is not ready', details: {} }
    });
  });
});

test('request ID propagates to successful responses and safe error responses', async () => {
  const app = createApp(config, createLogger(config));
  await withServer(app, async baseUrl => {
    const ok = await fetch(`${baseUrl}/health`, { headers: { 'x-request-id': 'trace-123' } });
    assert.equal(ok.headers.get('x-request-id'), 'trace-123');
    const missing = await fetch(`${baseUrl}/not-found`, { headers: { 'x-request-id': 'trace-456' } });
    assert.equal(missing.headers.get('x-request-id'), 'trace-456');
    assert.equal((await missing.json()).requestId, 'trace-456');
  });
});
