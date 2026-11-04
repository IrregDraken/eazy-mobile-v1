import assert from 'node:assert/strict';
import test from 'node:test';
import { profilePatchSchema, ProfileService } from '../src/modules/profiles/service.js';
import { mediaUploadSchema } from '../src/modules/media/schemas.js';
import type { ProfileRepository } from '../src/modules/profiles/repository.js';

test('profile patch accepts partial fields and normalizes username', () => {
  const parsed = profilePatchSchema.parse({ username: 'New_User', dateOfBirth: '1990-02-28', bio: null });
  assert.equal(parsed.username, 'new_user');
  assert.equal(parsed.dateOfBirth, '1990-02-28');
});

test('profile validation accepts empty optional middle and last names as omitted', () => {
  const parsed = profilePatchSchema.parse({ firstName: 'Draken', middleName: '   ', lastName: '' });
  assert.equal(parsed.middleName, undefined);
  assert.equal(parsed.lastName, undefined);
});
test('profile validation rejects invalid usernames and impossible dates', () => {
  assert.throws(() => profilePatchSchema.parse({ username: 'bad name' }));
  assert.throws(() => profilePatchSchema.parse({ dateOfBirth: '2023-02-29' }));
  assert.throws(() => profilePatchSchema.parse({ dateOfBirth: '2024-02-31' }));
});

test('public profile projection excludes date of birth and internal identity', async () => {
  const repository = {
    getPublicByUsername: async () => ({ username: 'public_user', display_name: 'Public User', first_name: 'Public', last_name: 'User', bio: 'Hello', avatar_url: 'https://cdn.example/avatar.png', cover_url: null, location: 'Lagos', onboarding_status: 'onboarding_complete' as const }),
    usernameAvailable: async () => true
  } as unknown as ProfileRepository;
  const service = new ProfileService({} as never, repository);
  const result = await service.getPublic('PUBLIC_USER');
  assert.deepEqual(result, { username: 'public_user', displayName: 'Public User', firstName: 'Public', lastName: 'User', bio: 'Hello', location: 'Lagos', avatarUrl: 'https://cdn.example/avatar.png', coverUrl: null });
  assert.equal('dateOfBirth' in result, false);
  assert.equal('userId' in result, false);
});

test('profile patch accepts an Eazy cover storage path and a public location', () => {
  const parsed = profilePatchSchema.parse({
    coverUrl: 'user-id/cover/cover-image.webp',
    location: 'Port Harcourt, Rivers',
  });
  assert.equal(parsed.coverUrl, 'user-id/cover/cover-image.webp');
  assert.equal(parsed.location, 'Port Harcourt, Rivers');
  assert.throws(() => profilePatchSchema.parse({ coverUrl: 'http://cdn.example/cover.webp' }));
  assert.throws(() => profilePatchSchema.parse({ location: 'x'.repeat(121) }));
  assert.equal(
    mediaUploadSchema.parse({ contentType: 'image/webp', kind: 'cover' }).kind,
    'cover',
  );
});
