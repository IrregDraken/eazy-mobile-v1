import assert from 'node:assert/strict';
import test from 'node:test';
import { Router } from 'express';
import { FirebaseAuthProvider } from '../src/providers/firebase-auth.js';
import { loadConfig } from '../src/config/env.js';
import { AppError } from '../src/middleware/errors.js';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { createFirebaseAuthenticationMiddleware } from '../src/modules/auth/routes.js';
import { createEmailVerificationRouter } from '../src/modules/auth/email-verification-routes.js';

const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent' });

test('Firebase provider refuses to initialize without server credentials', () => {
  assert.throws(() => new FirebaseAuthProvider(config), (error: unknown) => error instanceof AppError && error.code === 'SERVICE_UNAVAILABLE');
});

test('auth endpoints do not provide fake authentication when Firebase is unavailable', async () => {
  const app = createApp(config, createLogger(config));
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    for (const path of ['/v1/auth/me', '/v1/auth/session', '/v1/auth/logout']) {
      const response: Response = await fetch(`http://127.0.0.1:${address.port}${path}`, { method: path.endsWith('logout') ? 'POST' : 'GET' });
      const body = await response.json();
      assert.equal(response.status, 503);
      assert.equal(body.success, false);
      assert.equal(body.error.code, 'SERVICE_UNAVAILABLE');
      assert.equal(body.requestId, response.headers.get('x-request-id'));
    }
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});


test('unverified password identities are rejected before application account provisioning', async () => {
  let provisionCalls = 0;
  const provider = {
    verifyIdentity: async () => ({
      firebaseUid: 'firebase-user',
      claims: {
        email: 'pending@example.com',
        email_verified: false,
        firebase: { sign_in_provider: 'password' }
      }
    })
  };
  const authService = {
    provision: async () => {
      provisionCalls += 1;
      return { context: { userId: 'user-1', provider: 'firebase', claims: {} } };
    }
  };
  const app = createApp(config, createLogger(config), {
    authMiddleware: createFirebaseAuthenticationMiddleware(
      provider as never,
      authService as never
    ),
    profileRouter: (() => {
      const router = Router();
      router.get('/probe', (_request, response) => response.json({ success: true }));
      return router;
    })()
  });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/profiles/probe`, {
      headers: { authorization: 'Bearer pending-token' }
    });
    assert.equal(response.status, 403);
    assert.equal(provisionCalls, 0);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
});


test('unverified registration identity can bind a verified email challenge without provisioning first', async () => {
  let provisionCalls = 0;
  let markVerifiedCalls = 0;
  const provider = {
    verifyIdentity: async () => ({
      firebaseUid: 'firebase-new-user',
      claims: { email: 'new-user@example.com', email_verified: false }
    }),
    markEmailVerified: async (uid: string) => {
      assert.equal(uid, 'firebase-new-user');
      markVerifiedCalls += 1;
    }
  };
  const authService = {
    provision: async () => {
      provisionCalls += 1;
      return { context: { userId: 'user-1', provider: 'firebase', claims: {} } };
    }
  };
  const emailVerificationRouter = createEmailVerificationRouter(
    {
      verifyCode: async (challengeId: string, code: string) => {
        assert.equal(challengeId, '11111111-1111-4111-8111-111111111111');
        assert.equal(code, '123456');
        return { challengeId, email: 'new-user@example.com', verified: true as const };
      }
    } as never,
    provider as never
  );
  const app = createApp(config, createLogger(config), {
    authMiddleware: createFirebaseAuthenticationMiddleware(
      provider as never,
      authService as never
    ),
    emailVerificationRouter
  });
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    const response = await fetch(
      `http://127.0.0.1:${address.port}/v1/auth/email-verification/verify-code`,
      {
        method: 'POST',
        headers: {
          authorization: 'Bearer pending-token',
          'content-type': 'application/json'
        },
        body: JSON.stringify({
          challengeId: '11111111-1111-4111-8111-111111111111',
          code: '123456'
        })
      }
    );
    assert.equal(response.status, 200);
    assert.equal(markVerifiedCalls, 1);
    assert.equal(provisionCalls, 0);
  } finally {
    await new Promise<void>((resolve, reject) =>
      server.close(error => error ? reject(error) : resolve())
    );
  }
});
