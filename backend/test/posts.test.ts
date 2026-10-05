import assert from 'node:assert/strict';
import test from 'node:test';
import { createPostSchema, PostService } from '../src/modules/posts/service.js';
import { AppError } from '../src/middleware/errors.js';
import type { PostRepository } from '../src/modules/posts/repository.js';

function fakePool() {
  const client = { query: async () => undefined, release: () => undefined };
  return { connect: async () => client } as never;
}

test('post input validates content, supported visibility, and unique media positions', () => {
  const parsed = createPostSchema.parse({ content: 'Hello', visibility: 'followers', media: [{ storageKey: 'user/path/image.jpg', mediaType: 'image', position: 0 }] });
  assert.equal(parsed.visibility, 'followers');
  assert.throws(() => createPostSchema.parse({ content: '', visibility: 'public' }));
  assert.throws(() => createPostSchema.parse({ content: 'Hello', visibility: 'friends' }));
});

test('post service rejects duplicate media positions before database work', async () => {
  const repository = {} as PostRepository;
  const service = new PostService(fakePool(), repository);
  await assert.rejects(() => service.create('user-id', { content: 'Hello', visibility: 'public', media: [
    { storageKey: 'a', mediaType: 'image', position: 0 },
    { storageKey: 'b', mediaType: 'image', position: 0 }
  ] }), (error: unknown) => error instanceof AppError && error.code === 'VALIDATION_ERROR');
});

test('post deletion returns not found when ownership does not match', async () => {
  const repository = { softDelete: async () => false } as unknown as PostRepository;
  const service = new PostService(fakePool(), repository);
  await assert.rejects(() => service.delete('00000000-0000-0000-0000-000000000001', 'other-user'), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
});
