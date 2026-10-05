import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../src/middleware/errors.js';
import { searchQuerySchema, SocialService } from '../src/modules/social/service.js';
import type { SocialRepository } from '../src/modules/social/repository.js';

function fakePool() {
  const client = { query: async () => undefined, release: () => undefined };
  return { connect: async () => client } as never;
}

function repository(overrides: Partial<Record<keyof SocialRepository, unknown>> = {}) {
  return {
    targetByUsername: async (_client: unknown, username: string) => ({ id: username === 'other_user' ? 'other' : 'target', username }),
    isBlocked: async () => false,
    follow: async () => true,
    unfollow: async () => false,
    block: async () => true,
    unblock: async () => false,
    relationship: async () => ({ following: true, followed_by: false, blocked: false, blocked_by: false }),
    list: async () => ({ items: [], total: 0 }),
    blocks: async () => ({ items: [], total: 0 }),
    search: async () => ({ items: [], total: 0 }),
    report: async () => 'report-id',
    ...overrides
  } as unknown as SocialRepository;
}

test('follow is server-owned, rejects self-follow, and handles duplicate safely', async () => {
  const service = new SocialService(fakePool(), repository());
  assert.deepEqual(await service.follow('me', 'other_user'), { following: true, username: 'other_user' });
  const selfService = new SocialService(fakePool(), repository({ targetByUsername: async () => ({ id: 'me', username: 'self_user' }) }));
  await assert.rejects(() => selfService.follow('me', 'self_user'), (error: unknown) => error instanceof AppError && error.code === 'BAD_REQUEST');
  const duplicate = new SocialService(fakePool(), repository({ follow: async () => false }));
  assert.deepEqual(await duplicate.follow('me', 'other_user'), { following: true, username: 'other_user' });
});

test('blocked relationships reject follow and block is reciprocal-safe', async () => {
  const service = new SocialService(fakePool(), repository({ isBlocked: async () => true }));
  await assert.rejects(() => service.follow('me', 'other_user'), (error: unknown) => error instanceof AppError && error.code === 'FORBIDDEN');
  const block = new SocialService(fakePool(), repository());
  assert.deepEqual(await block.block('me', 'other_user'), { blocked: true, created: true, username: 'other_user' });
  assert.deepEqual(await block.unblock('me', 'other_user'), { blocked: false, removed: false, username: 'other_user' });
});

test('relationship state and paginated list metadata are safe projections', async () => {
  const service = new SocialService(fakePool(), repository({ relationship: async () => ({ following: true, followed_by: true, blocked: false, blocked_by: false }), list: async () => ({ items: [{ username: 'other_user', displayName: 'Other', avatarUrl: null }], total: 21 }) }));
  assert.deepEqual(await service.relationship('me', 'other_user'), { following: true, followedBy: true, blocked: false, blockedBy: false, self: false });
  const list = await service.list(undefined, 'followers', 'other_user', { page: 2, limit: 10, cursor: undefined });
  assert.equal(list.items[0]?.username, 'other_user');
  assert.deepEqual(list.meta, { page: 2, limit: 10, cursor: null, total: 21, pages: 3 });
});

test('search query validation bounds input and report rejects self-reporting', async () => {
  const service = new SocialService(fakePool(), repository());
  assert.throws(() => searchQuerySchema.parse({ q: 'x', page: 1, limit: 20 }));
  const selfService = new SocialService(fakePool(), repository({ targetByUsername: async () => ({ id: 'me', username: 'self_user' }) }));
  await assert.rejects(() => selfService.report('me', 'self_user', 'spam'), (error: unknown) => error instanceof AppError && error.code === 'BAD_REQUEST');
});
