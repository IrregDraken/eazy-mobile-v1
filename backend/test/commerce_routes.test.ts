import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { createCartRouter } from '../src/modules/cart/routes.js';
import { createOrderRouter } from '../src/modules/orders/routes.js';
import type { CartService } from '../src/modules/cart/service.js';
import type { OrderService } from '../src/modules/orders/service.js';

const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

const cart = {} as CartService;
const orders = {} as OrderService;

test('cart and order operations require authentication', async () => {
  const app = createApp(config, createLogger(config), { cartRouter: createCartRouter(cart), orderRouter: createOrderRouter(orders) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const requests = [
      fetch(`http://127.0.0.1:${address.port}/v1/cart`),
      fetch(`http://127.0.0.1:${address.port}/v1/cart/items`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ productId: '00000000-0000-0000-0000-000000000001', quantity: 1 }) }),
      fetch(`http://127.0.0.1:${address.port}/v1/orders`, { method: 'POST', headers: { 'idempotency-key': 'test-key-123' } })
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
