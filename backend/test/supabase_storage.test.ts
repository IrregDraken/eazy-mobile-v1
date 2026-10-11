import assert from 'node:assert/strict';
import test from 'node:test';
import http from 'node:http';
import { SupabaseStorageProvider } from '../src/providers/supabase-storage.js';

function config(url: string) {
  return { SUPABASE_URL: url, SUPABASE_SERVICE_ROLE_KEY: 'secret-test-key', MEDIA_BUCKET: 'eazy-media' } as never;
}

async function serverWith(handler: (request: http.IncomingMessage, body: string) => { status?: number; body?: unknown }) {
  const calls: { path: string; body: string; auth: string | undefined }[] = [];
  const server = http.createServer((request, response) => {
    let body = '';
    request.on('data', chunk => { body += String(chunk); });
    request.on('end', () => {
      calls.push({ path: request.url ?? '', body, auth: request.headers.authorization });
      const result = handler(request, body);
      response.statusCode = result.status ?? 200;
      response.setHeader('content-type', 'application/json');
      response.end(JSON.stringify(result.body ?? {}));
    });
  });
  await new Promise<void>(resolve => server.listen(0, '127.0.0.1', () => resolve()));
  const address = server.address() as { port: number };
  return { server, calls, url: `http://127.0.0.1:${address.port}` };
}

test('storage cleanup deletes exact keys in bounded batches and never sends the service key in the body', async () => {
  const fixture = await serverWith(() => ({}));
  try {
    const provider = new SupabaseStorageProvider(config(fixture.url));
    const paths = Array.from({ length: 201 }, (_, index) => `user-a/post/2026-10-10/${index}.jpg`);
    const result = await provider.deleteObjects(paths);
    assert.deepEqual(result, { deleted: 201, requested: 201 });
    assert.equal(fixture.calls.length, 3);
    assert.deepEqual(fixture.calls.map(call => JSON.parse(call.body).prefixes.length), [100, 100, 1]);
    assert.ok(fixture.calls.every(call => call.path === '/storage/v1/object/remove/eazy-media'));
    assert.ok(fixture.calls.every(call => call.auth === 'Bearer secret-test-key'));
    assert.ok(fixture.calls.every(call => !call.body.includes('secret-test-key')));
  } finally { await new Promise<void>(resolve => fixture.server.close(() => resolve())); }
});

test('storage cleanup retries transient provider failures and treats a later success as complete', async () => {
  let attempts = 0;
  const fixture = await serverWith(() => {
    attempts += 1;
    return attempts < 3 ? { status: 503, body: { message: 'temporary outage' } } : {};
  });
  try {
    const provider = new SupabaseStorageProvider(config(fixture.url));
    assert.deepEqual(await provider.deleteObjects(['user-a/avatar/2026-10-10/a.png']), { deleted: 1, requested: 1 });
    assert.equal(attempts, 3);
  } finally { await new Promise<void>(resolve => fixture.server.close(() => resolve())); }
});

test('storage cleanup rejects paths that are not exact safe object keys', async () => {
  const fixture = await serverWith(() => ({}));
  try {
    const provider = new SupabaseStorageProvider(config(fixture.url));
    await assert.rejects(() => provider.deleteObjects(['/user-a/avatar/x.png']), /invalid object path/);
    await assert.rejects(() => provider.deleteObjects(['user-a/../other/x.png']), /invalid object path/);
    assert.equal(fixture.calls.length, 0);
  } finally { await new Promise<void>(resolve => fixture.server.close(() => resolve())); }
});
