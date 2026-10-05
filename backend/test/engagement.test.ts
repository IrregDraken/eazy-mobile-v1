import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../src/middleware/errors.js';
import { commentSchema, EngagementService } from '../src/modules/engagement/service.js';
import type { EngagementRepository } from '../src/modules/engagement/repository.js';

function fakePool() {
  const client = { query: async () => undefined, release: () => undefined };
  return { connect: async () => client } as never;
}

function repository(overrides: Partial<Record<keyof EngagementRepository, unknown>> = {}) {
  return {
    assertAccessiblePost: async () => undefined,
    like: async () => true,
    unlike: async () => false,
    createComment: async () => ({ id: 'comment-id', content: 'hello', createdAt: '2026-01-01T00:00:00Z', author: { username: 'author', displayName: 'Author', avatarUrl: null } }),
    listComments: async () => ({ items: [], total: 0 }),
    deleteComment: async () => false,
    save: async () => true,
    unsave: async () => false,
    savedPosts: async () => ({ items: [], total: 0 }),
    ...overrides
  } as unknown as EngagementRepository;
}

test('likes and saves are idempotent and user-owned', async () => {
  const service = new EngagementService(fakePool(), repository());
  assert.deepEqual(await service.like('00000000-0000-0000-0000-000000000001', 'user-id'), { liked: true, created: true });
  assert.deepEqual(await service.unlike('00000000-0000-0000-0000-000000000001', 'user-id'), { liked: false, removed: false });
  assert.deepEqual(await service.save('00000000-0000-0000-0000-000000000001', 'user-id'), { saved: true, created: true });
  assert.deepEqual(await service.unsave('00000000-0000-0000-0000-000000000001', 'user-id'), { saved: false, removed: false });
});

test('inaccessible posts cannot be engaged', async () => {
  const repositoryMock = repository({ assertAccessiblePost: async () => { throw new Error('POST_INACCESSIBLE'); } });
  const service = new EngagementService(fakePool(), repositoryMock);
  await assert.rejects(() => service.like('00000000-0000-0000-0000-000000000001', 'user-id'), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
  await assert.rejects(() => service.createComment('00000000-0000-0000-0000-000000000001', 'user-id', 'hello'), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
});

test('comments validate content and enforce author ownership on deletion', async () => {
  assert.equal(commentSchema.parse({ content: ' hello ' }).content, 'hello');
  assert.throws(() => commentSchema.parse({ content: '' }));
  const service = new EngagementService(fakePool(), repository());
  await assert.rejects(() => service.deleteComment('00000000-0000-0000-0000-000000000002', 'other-user'), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
});

test('saved posts return bounded pagination metadata', async () => {
  const repositoryMock = repository({ savedPosts: async () => ({ items: [{ id: 'post-id' }], total: 21 }) });
  const service = new EngagementService(fakePool(), repositoryMock);
  const result = await service.savedPosts('user-id', { page: 2, limit: 10, cursor: undefined });
  assert.equal(result.items.length, 1);
  assert.deepEqual(result.meta, { page: 2, limit: 10, cursor: null, total: 21, pages: 3 });
});
