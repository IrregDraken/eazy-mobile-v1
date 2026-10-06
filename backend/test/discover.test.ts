import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../src/middleware/errors.js';
import { DiscoverService } from '../src/modules/discover/service.js';
import { MarketplaceService } from '../src/modules/marketplace/service.js';
import type { MarketplaceRepository } from '../src/modules/marketplace/repository.js';
import type { SocialService } from '../src/modules/social/service.js';

function fakePool() {
  const client = { query: async () => undefined, release: () => undefined };
  return { connect: async () => client } as never;
}

test('unified people discovery reuses the existing social search service and requires authentication', async () => {
  let called = false;
  const social = { search: async (userId: string, input: { q: string }) => { called = userId === 'user-id' && input.q === 'alice'; return { items: [], meta: { page: 1, limit: 20, total: 0, pages: 0, cursor: null } }; } } as unknown as SocialService;
  const marketplace = new MarketplaceService(fakePool(), { categories: async () => [], products: async () => ({ items: [], total: 0 }), getById: async () => null, create: async () => 'id', update: async () => true, updateInventory: async () => true } as unknown as MarketplaceRepository);
  const service = new DiscoverService(marketplace, social);
  await service.unified({ type: 'people', q: 'alice', sort: 'newest', page: 1, limit: 20 }, 'user-id');
  assert.equal(called, true);
  await assert.rejects(() => service.unified({ type: 'people', q: 'alice', sort: 'newest', page: 1, limit: 20 }), (error: unknown) => error instanceof AppError && error.code === 'UNAUTHORIZED');
});

test('unified categories discovery reads database-backed categories through marketplace service', async () => {
  const marketplace = new MarketplaceService(fakePool(), { categories: async () => ({ items: [{ id: 'category-id', name: 'Books', slug: 'books' }], total: 1 }), products: async () => ({ items: [], total: 0 }), getById: async () => null, create: async () => 'id', update: async () => true, updateInventory: async () => true } as unknown as MarketplaceRepository);
  const service = new DiscoverService(marketplace, {} as SocialService);
  const result = await service.unified({ type: 'categories', sort: 'newest', page: 1, limit: 20 });
  assert.equal(result.type, 'categories');
  assert.equal((result.items as { slug: string }[])[0]?.slug, 'books');
});


test('unified product discovery projects out the discovery type discriminator', async () => {
  let received: Record<string, unknown> | undefined;
  const marketplace = {
    search: async (input: Record<string, unknown>) => {
      received = input;
      return { items: [], meta: { page: 1, limit: 20, total: 0, pages: 0, cursor: null } };
    },
    categories: async () => ({ items: [], total: 0 })
  } as unknown as MarketplaceService;
  const service = new DiscoverService(marketplace, {} as SocialService);
  const result = await service.unified({ type: 'products', sort: 'newest', page: 1, limit: 20 });
  assert.equal(result.type, 'products');
  assert.equal(received?.type, undefined);
  assert.equal(received?.sort, 'newest');
});
