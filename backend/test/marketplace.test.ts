import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../src/middleware/errors.js';
import { MarketplaceService, productCreateSchema, productSearchSchema, productUpdateSchema } from '../src/modules/marketplace/service.js';
import { MarketplaceRepository, type MarketplaceRepository as MarketplaceRepositoryContract } from '../src/modules/marketplace/repository.js';

function fakePool() {
  const client = { query: async () => undefined, release: () => undefined };
  return { connect: async () => client } as never;
}

function repository(overrides: Partial<Record<keyof MarketplaceRepositoryContract, unknown>> = {}) {
  return {
    categories: async () => [{ id: 'category-id', name: 'Books', slug: 'books' }],
    products: async () => ({ items: [], total: 0 }),
    getById: async () => ({ id: 'product-id', name: 'Book', description: null, priceAmount: '10.00', currency: 'USD', status: 'draft', createdAt: '2026-01-01T00:00:00Z', category: null, seller: { username: 'seller', displayName: 'Seller', avatarUrl: null }, media: [], availability: { inStock: true } }),
    create: async () => 'product-id',
    update: async () => true,
    updateInventory: async () => true,
    ...overrides
  } as unknown as MarketplaceRepositoryContract;
}

test('product schema preserves exact decimal prices and restricts currency/status', () => {
  const value = productCreateSchema.parse({ name: 'Book', priceAmount: '10.25', currency: 'usd' });
  assert.equal(value.priceAmount, '10.25');
  assert.equal(value.currency, 'USD');
  assert.equal(value.status, 'draft');
  assert.throws(() => productCreateSchema.parse({ name: 'Book', priceAmount: '10.257', currency: 'USD' }));
  assert.throws(() => productCreateSchema.parse({ name: 'Book', priceAmount: '-1.00', currency: 'USD' }));
});

test('product update requires an explicit allowed field and cannot include seller identity', () => {
  assert.deepEqual(productUpdateSchema.parse({ priceAmount: '12.00' }), { priceAmount: '12.00' });
  assert.throws(() => productUpdateSchema.parse({}));
  assert.throws(() => productUpdateSchema.parse({ sellerId: '00000000-0000-0000-0000-000000000001' }));
});

test('marketplace service rejects duplicate media positions and preserves seller ownership boundary', async () => {
  const service = new MarketplaceService(fakePool(), repository());
  await assert.rejects(() => service.create('seller-id', { name: 'Book', description: undefined, categoryId: undefined, priceAmount: '10.00', currency: 'USD', status: 'draft', availableQuantity: 1, media: [{ storageKey: 'a', position: 0 }, { storageKey: 'b', position: 0 }] }), (error: unknown) => error instanceof AppError && error.code === 'VALIDATION_ERROR');
  const updated = await service.update('product-id', 'seller-id', { priceAmount: '11.00' });
  assert.equal(updated.product.id, 'product-id');
});

test('product search validates bounded filters and deterministic sort options', () => {
  const query = productSearchSchema.parse({ q: 'book', minPrice: '1.00', maxPrice: '20.00', sort: 'price_asc', limit: '10' });
  assert.equal(query.sort, 'price_asc');
  assert.equal(query.limit, 10);
  assert.equal(productSearchSchema.parse({ q: 'book', maxPrice: '50000', currency: 'ngn' }).currency, 'NGN');
  assert.throws(() => productSearchSchema.parse({ q: 'x' }));
  assert.throws(() => productSearchSchema.parse({ minPrice: '20.00', maxPrice: '1.00' }));
});

test('marketplace currency budget filter is parameterized for both count and product queries', async () => {
  const calls: { sql: string; values: unknown[] }[] = [];
  const pool = {
    query: async (sql: string, values: unknown[] = []) => {
      calls.push({ sql, values });
      return { rows: sql.startsWith('SELECT count(*)') ? [{ count: '0' }] : [], rowCount: 0 };
    }
  };
  const repository = new MarketplaceRepository(pool as never);
  await repository.products({ q: 'backpack%', maxPrice: '50000', currency: 'NGN', availability: 'in_stock', status: 'active', sort: 'newest', page: 1, limit: 5, viewerId: 'viewer-id' });
  assert.equal(calls.length, 2);
  for (const call of calls) {
    assert.match(call.sql, /upper\(trim\(p\.currency\)\) = \$3/);
    assert.equal(call.values[2], 'NGN');
    assert.doesNotMatch(call.sql, /NGN/);
  }
});
