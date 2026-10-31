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
import { AuthService } from '../src/modules/auth/service.js';

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


test('auth provisioning returns onboarding status for existing profiles', async () => {
  const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
  const createdAt = new Date().toISOString();
  const profile = {
    user_id: 'user-1',
    username: 'existing_user',
    display_name: 'Existing User',
    onboarding_status: 'onboarding_complete'
  };
  const client = {
    query: async (sql: string) => {
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes('INSERT INTO users')) {
        return { rows: [{ id: 'user-1', firebase_uid: 'firebase-user', email: 'existing@example.com', phone: null, status: 'active' }], rowCount: 1 };
      }
      if (sql.includes('FROM profiles WHERE user_id = $1')) {
        return { rows: [profile], rowCount: 1 };
      }
      if (sql.includes('INSERT INTO sessions')) {
        return { rows: [{ id: 'session-1' }], rowCount: 1 };
      }
      if (sql.includes('SELECT id, expires_at, created_at FROM sessions')) {
        return { rows: [{ id: 'session-1', expires_at: expiresAt, created_at: createdAt }], rowCount: 1 };
      }
      if (sql.includes('UPDATE sessions SET last_activity_at')) {
        return { rows: [{ revoked_at: null, expires_at: expiresAt }], rowCount: 1 };
      }
      if (sql.includes('INSERT INTO security_events')) {
        return { rows: [], rowCount: 1 };
      }
      throw new Error('Unexpected auth test query: ' + sql);
    },
    release: () => undefined
  };
  const pool = { connect: async () => client } as never;
  const service = new AuthService(pool, config);
  const result = await service.provision({
    firebaseUid: 'firebase-user',
    claims: {
      auth_time: Math.floor(Date.now() / 1000),
      email: 'existing@example.com',
      email_verified: true
    }
  });
  assert.equal(result.context.account.profile?.onboarding_status, 'onboarding_complete');
});
