import assert from 'node:assert/strict';
import test from 'node:test';
import express from 'express';
import { createAuthRouter } from '../src/modules/auth/routes.js';
import { errorHandler } from '../src/middleware/errors.js';

test('delete-account route requires auth, the DELETE confirmation, and calls the service', async () => {
  const calls: string[] = [];
  const deletion = { preflight: async () => ({ canDelete: true, blockers: [] }), deleteAccount: async (id: string) => { calls.push(id); return { deleted: true as const }; } };
  const app = express(); app.use(express.json());
  app.use((req, _res, next) => { if (req.header('x-test-user')) req.auth = { userId: req.header('x-test-user')!, provider: 'firebase', claims: {}, sessionId: 's', firebaseUid: 'f' } as never; next(); });
  app.use('/v1/auth', createAuthRouter({} as never, deletion as never));
  app.use(errorHandler({ error: () => undefined }));
  const server = app.listen(0); const port = (server.address() as { port: number }).port;
  const call = (path: string, init: RequestInit = {}) => fetch(`http://127.0.0.1:${port}/v1/auth${path}`, { ...init, headers: { 'content-type': 'application/json', ...(init.headers as object) } });
  try {
    assert.equal((await call('/delete-account', { method: 'POST', body: JSON.stringify({ confirmation: 'DELETE' }) })).status, 401);
    assert.equal((await call('/delete-account', { method: 'POST', headers: { 'x-test-user': 'u1' }, body: JSON.stringify({ confirmation: 'nope' }) })).status, 422);
    assert.equal((await call('/delete-account', { method: 'POST', headers: { 'x-test-user': 'u1' }, body: JSON.stringify({}) })).status, 422);
    const ok = await call('/delete-account', { method: 'POST', headers: { 'x-test-user': 'u1' }, body: JSON.stringify({ confirmation: 'DELETE' }) });
    assert.equal(ok.status, 200); assert.deepEqual((await ok.json()).data, { deleted: true }); assert.deepEqual(calls, ['u1']);
    const pre = await call('/delete-account/preflight', { headers: { 'x-test-user': 'u1' } });
    assert.equal(pre.status, 200); assert.equal((await pre.json()).data.canDelete, true);
  } finally { await new Promise<void>(r => server.close(() => r())); }
});
