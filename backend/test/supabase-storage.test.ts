import assert from 'node:assert/strict';
import test from 'node:test';
import { SupabaseStorageProvider } from '../src/providers/supabase-storage.js';

test('signed upload URL request does not send an empty JSON body', async () => {
  const originalFetch = globalThis.fetch;
  let capturedHeaders: Headers | undefined;
  let capturedBody: BodyInit | null | undefined;

  globalThis.fetch = async (_input, init) => {
    capturedHeaders = new Headers(init?.headers);
    capturedBody = init?.body;
    return new Response(
      JSON.stringify({
        url: '/object/upload/sign/eazy-media/user/avatar/test.jpg?token=upload-token'
      }),
      { status: 200, headers: { 'content-type': 'application/json' } }
    );
  };

  try {
    const provider = new SupabaseStorageProvider({
      SUPABASE_URL: 'https://example-project.supabase.co',
      SUPABASE_SERVICE_ROLE_KEY: 'test-service-role-key',
      MEDIA_BUCKET: 'eazy-media'
    } as never);

    const result = await provider.createSignedUploadUrl('user/avatar/test.jpg');

    assert.equal(capturedBody, undefined);
    assert.equal(capturedHeaders?.has('content-type'), false);
    assert.equal(capturedHeaders?.get('authorization'), 'Bearer test-service-role-key');
    assert.equal(capturedHeaders?.get('apikey'), 'test-service-role-key');
    assert.equal(result.token, 'upload-token');
    assert.equal(
      result.signedUrl,
      'https://example-project.supabase.co/storage/v1/object/upload/sign/eazy-media/user/avatar/test.jpg?token=upload-token'
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
