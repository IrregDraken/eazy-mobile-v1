import assert from 'node:assert/strict';
import test from 'node:test';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { createMarketplaceRouter } from '../src/modules/marketplace/routes.js';
import { createDiscoverRouter } from '../src/modules/discover/routes.js';
import type { MarketplaceService } from '../src/modules/marketplace/service.js';
import type { DiscoverService } from '../src/modules/discover/service.js';

const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

const marketplace = {
  categories: async () => ({ items: [], meta: { page: 1, limit: 20, total: 0, pages: 0, cursor: null } }),
  search: async () => ({ items: [], meta: { page: 1, limit: 20, total: 0, pages: 0, cursor: null } }),
  detail: async () => ({ product: {} }),
  create: async () => ({ product: {} }),
  update: async () => ({ product: {} }),
  updateInventory: async () => ({ product: {} })
} as unknown as MarketplaceService;
const discover = { unified: async () => ({ type: 'categories', items: [] }), products: async () => ({ items: [], meta: {} }) } as unknown as DiscoverService;

test('marketplace mutations require authentication while public discovery remains readable', async () => {
  const app = createApp(config, createLogger(config), { marketplaceRouter: createMarketplaceRouter(marketplace), discoverRouter: createDiscoverRouter(discover) });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const createResponse = await fetch(`http://127.0.0.1:${address.port}/v1/marketplace/products`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ name: 'Test', priceAmount: '1.00', currency: 'USD' }) });
    assert.equal(createResponse.status, 401);
    const products = await fetch(`http://127.0.0.1:${address.port}/v1/discover/products?q=book`);
    assert.equal(products.status, 200);
    const categories = await fetch(`http://127.0.0.1:${address.port}/v1/discover/categories?page=1&limit=10`);
    assert.equal(categories.status, 200);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});
