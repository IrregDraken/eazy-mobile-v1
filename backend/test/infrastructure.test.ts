import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError, toAppError } from '../src/middleware/errors.js';
import { paginationMeta, paginationQuerySchema } from '../src/utils/pagination.js';
import { idempotencyKey } from '../src/middleware/idempotency.js';
import { createRateLimiter } from '../src/middleware/rate-limit.js';
import { requireAuth, createAuthenticationMiddleware } from '../src/middleware/auth.js';
import { createDbPool } from '../src/database/client.js';
import { loadConfig } from '../src/config/env.js';
import { fetchWithTimeout } from '../src/utils/fetch.js';

function request(headers: Record<string, string> = {}) {
  return { header: (key: string) => headers[key.toLowerCase()] } as never;
}

test('typed errors map to safe codes and unknown errors become internal errors', () => {
  assert.equal(new AppError('CONFLICT', 'Conflict').statusCode, 409);
  assert.equal(toAppError(new Error('secret')).code, 'INTERNAL_ERROR');
});

test('pagination applies safe defaults, max limits, and metadata', () => {
  const parsed = paginationQuerySchema.parse({});
  assert.deepEqual(parsed, { page: 1, limit: 20 });
  assert.throws(() => paginationQuerySchema.parse({ limit: 101 }));
  assert.deepEqual(paginationMeta(parsed, 45), { page: 1, limit: 20, cursor: null, total: 45, pages: 3 });
});

test('idempotency key requires a valid scoped header value', () => {
  assert.equal(idempotencyKey(request({ 'idempotency-key': 'valid-key-123' })), 'valid-key-123');
  assert.throws(() => idempotencyKey(request()), (error: unknown) => error instanceof AppError && error.code === 'VALIDATION_ERROR');
});

test('auth hook rejects unauthenticated access and accepts verified context', () => {
  let error: unknown;
  requireAuth({ auth: undefined } as never, {} as never, value => { error = value; });
  assert.ok(error instanceof AppError && error.code === 'UNAUTHORIZED');
  const middleware = createAuthenticationMiddleware({ authenticate: async token => ({ userId: token, provider: 'test', claims: {} }) });
  let nextError: unknown;
  const authenticatedRequest = { header: () => 'Bearer server-verified-subject' } as never;
  middleware(authenticatedRequest, {} as never, value => { nextError = value; });
  assert.equal(nextError, undefined);
});

test('rate limiter rejects requests over policy', () => {
  const limiter = createRateLimiter({ name: 'test', windowMs: 60000, max: 1 });
  let error: unknown;
  const response = { setHeader: () => undefined } as never;
  const req = { ip: '127.0.0.1' } as never;
  limiter(req, response, () => undefined);
  limiter(req, response, value => { error = value; });
  assert.ok(error instanceof AppError && error.code === 'RATE_LIMITED');
});

test('database configuration failure is explicit and does not expose secrets', () => {
  const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent' });
  assert.throws(() => createDbPool(config), (error: unknown) => error instanceof AppError && error.code === 'SERVICE_UNAVAILABLE');
});


test('rate limiter enforces both authenticated-user and network budgets', () => {
  const response = { setHeader: () => undefined } as never;
  const perUser = createRateLimiter({ name: 'per-user', windowMs: 60_000, max: 1 });
  const firstUserRequest = { ip: '10.0.0.1', auth: { userId: 'user-1' } } as never;
  let userError: unknown;
  perUser(firstUserRequest, response, () => undefined);
  perUser(
    { ip: '10.0.0.2', auth: { userId: 'user-1' } } as never,
    response,
    error => { userError = error; },
  );
  assert.ok(userError instanceof AppError && userError.code === 'RATE_LIMITED');

  const perIp = createRateLimiter({ name: 'per-ip', windowMs: 60_000, max: 1 });
  const firstIpRequest = { ip: '10.0.0.3', auth: { userId: 'user-1' } } as never;
  let ipError: unknown;
  perIp(firstIpRequest, response, () => undefined);
  perIp(
    { ip: '10.0.0.3', auth: { userId: 'user-2' } } as never,
    response,
    error => { ipError = error; },
  );
  assert.ok(ipError instanceof AppError && ipError.code === 'RATE_LIMITED');
});


test('upstream fetch helper aborts and rejects when the provider exceeds its timeout', async () => {
  const originalFetch = globalThis.fetch;
  let observedSignal: AbortSignal | undefined;
  globalThis.fetch = async (_input, init) => {
    observedSignal = init?.signal ?? undefined;
    return new Promise<Response>(() => {});
  };
  try {
    await assert.rejects(
      () => fetchWithTimeout('https://provider.example.test', {}, 10),
      /Upstream request timed out/,
    );
    assert.equal(observedSignal?.aborted, true);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
