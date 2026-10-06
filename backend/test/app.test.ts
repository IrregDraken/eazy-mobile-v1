import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config/env.js';
import { createLogger } from '../src/config/logger.js';

const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent', CORS_ORIGIN: '*', RATE_LIMIT_MAX: '20' });
const app = createApp(config, createLogger(config));

async function withServer(run: (baseUrl: string) => Promise<void>) {
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
}

test('health and API root return standardized success responses', async () => {
  await withServer(async baseUrl => {
    const health = await fetch(`${baseUrl}/health`);
    assert.equal(health.status, 200);
    assert.deepEqual((await health.json()).success, true);
    const root = await fetch(`${baseUrl}/v1`);
    assert.equal(root.status, 200);
    assert.deepEqual((await root.json()).data, { version: 'v1', status: 'available' });
  });
});

test('rejected CORS requests return controlled 403 errors with request IDs', async () => {
  const corsConfig = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent', CORS_ORIGIN: 'https://app.example.test', RATE_LIMIT_MAX: '20' });
  const corsApp = createApp(corsConfig, createLogger(corsConfig));
  const server = corsApp.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const response = await fetch(`http://127.0.0.1:${address.port}/v1`, {
      headers: { Origin: 'https://evil.example' }
    });
    const body = await response.json();
    assert.equal(response.status, 403);
    assert.equal(body.success, false);
    assert.equal(body.error.code, 'FORBIDDEN');
    assert.equal(body.requestId, response.headers.get('x-request-id'));
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});

test('malformed JSON returns 400 with a request ID', async () => {
  await withServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/v1`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{"broken":'
    });
    const body = await response.json();
    assert.equal(response.status, 400);
    assert.equal(body.error.code, 'BAD_REQUEST');
    assert.equal(body.requestId, response.headers.get('x-request-id'));
  });
});

test('oversized JSON returns 413 with a request ID', async () => {
  await withServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/v1`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ payload: 'x'.repeat(1_048_576) })
    });
    const body = await response.json();
    assert.equal(response.status, 413);
    assert.equal(body.error.code, 'PAYLOAD_TOO_LARGE');
    assert.equal(body.requestId, response.headers.get('x-request-id'));
  });
});

test('unknown route returns standardized error with request ID', async () => {
  await withServer(async baseUrl => {
    const response = await fetch(`${baseUrl}/missing`);
    const body = await response.json();
    assert.equal(response.status, 404);
    assert.equal(body.success, false);
    assert.equal(body.error.code, 'NOT_FOUND');
    assert.equal(body.requestId, response.headers.get('x-request-id'));
  });
});
