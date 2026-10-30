import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';
import type { Pool } from 'pg';

import { createApp } from '../src/app.js';
import { loadConfig } from '../src/config/env.js';
import { createLogger } from '../src/config/logger.js';
import { AppError } from '../src/middleware/errors.js';
import type { FirebaseAuthProvider, FirebaseIdentity } from '../src/providers/firebase-auth.js';
import { EmailVerificationService } from '../src/modules/auth/email-verification.js';
import type { EmailProvider } from '../src/providers/resend-email.js';
import { createEmailVerificationRouter } from '../src/modules/auth/email-verification-routes.js';

const email = 'person@example.com';
const challengeId = '00000000-0000-4000-8000-000000000001';
const testOtpHmacSecret = 'eazy-non-production-only-otp-hmac-secret';

function createHarness(options: {
  identity?: FirebaseIdentity;
  emailExists?: boolean;
} = {}) {
  const identity = options.identity ?? {
    firebaseUid: 'firebase-user-1',
    claims: { email, email_verified: false }
  };
  const calls: Array<{ method: string; args: unknown[] }> = [];
  const verifiedUsers: string[] = [];

  const service = {
    requestCode: async (requestedEmail: string, requestOptions?: { allowExistingUnverified?: boolean }) => {
      calls.push({ method: 'requestCode', args: [requestedEmail, requestOptions] });
      return { challengeId, expiresInSeconds: 600 };
    },
    verifyCode: async (id: string, code: string, expectedEmail?: string) => {
      calls.push({ method: 'verifyCode', args: [id, code, expectedEmail] });
      if (expectedEmail && expectedEmail !== email) {
        throw new AppError('FORBIDDEN', 'Verification request does not match the authenticated account');
      }
      return { challengeId: id, email, verified: true as const };
    }
  };

  const provider = {
    emailExists: async (value: string) => {
      calls.push({ method: 'emailExists', args: [value] });
      return options.emailExists ?? false;
    },
    verifyIdentity: async (token: string) => {
      calls.push({ method: 'verifyIdentity', args: [token] });
      if (token !== 'valid-token') throw new AppError('UNAUTHORIZED', 'Invalid authentication');
      return identity;
    },
    markEmailVerified: async (uid: string) => {
      calls.push({ method: 'markEmailVerified', args: [uid] });
      verifiedUsers.push(uid);
    }
  };

  const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent' });
  const app = createApp(config, createLogger(config), {
    emailVerificationRouter: createEmailVerificationRouter(
      service as unknown as EmailVerificationService,
      provider as unknown as FirebaseAuthProvider
    )
  });

  return { app, calls, verifiedUsers };
}

async function withServer(
  app: ReturnType<typeof createApp>,
  run: (baseUrl: string) => Promise<void>
) {
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => {
      server.close(error => error ? reject(error) : resolve());
    });
  }
}

test('unauthenticated code requests reject an email already attached to Firebase', async () => {
  const harness = createHarness({ emailExists: true });
  await withServer(harness.app, async baseUrl => {
    const response = await fetch(`${baseUrl}/v1/auth/email-verification/request-code`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email })
    });
    assert.equal(response.status, 409);
    assert.equal(harness.calls.some(call => call.method === 'requestCode'), false);
  });
});

test('authenticated unverified accounts can request and resend their own code', async () => {
  const harness = createHarness();
  await withServer(harness.app, async baseUrl => {
    const response = await fetch(`${baseUrl}/v1/auth/email-verification/request-code`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer valid-token'
      },
      body: JSON.stringify({ email: email.toUpperCase() })
    });
    assert.equal(response.status, 200);
    assert.deepEqual(
      harness.calls.find(call => call.method === 'requestCode')?.args,
      [email, { allowExistingUnverified: true }]
    );
    assert.equal(harness.calls.some(call => call.method === 'emailExists'), false);
  });
});

test('authenticated code requests cannot target a different email or a verified account', async () => {
  const mismatch = createHarness();
  await withServer(mismatch.app, async baseUrl => {
    const response = await fetch(`${baseUrl}/v1/auth/email-verification/request-code`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer valid-token'
      },
      body: JSON.stringify({ email: 'other@example.com' })
    });
    assert.equal(response.status, 403);
    assert.equal(mismatch.calls.some(call => call.method === 'requestCode'), false);
  });

  const verified = createHarness({
    identity: {
      firebaseUid: 'firebase-user-1',
      claims: { email, email_verified: true }
    }
  });
  await withServer(verified.app, async baseUrl => {
    const response = await fetch(`${baseUrl}/v1/auth/email-verification/request-code`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer valid-token'
      },
      body: JSON.stringify({ email })
    });
    assert.equal(response.status, 409);
    assert.equal(verified.calls.some(call => call.method === 'requestCode'), false);
  });
});

test('pre-account verification can be completed and then bound to the matching Firebase account', async () => {
  const harness = createHarness();
  await withServer(harness.app, async baseUrl => {
    const preAccount = await fetch(`${baseUrl}/v1/auth/email-verification/verify-code`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ challengeId, code: '123456' })
    });
    assert.equal(preAccount.status, 200);
    assert.deepEqual(harness.verifiedUsers, []);
    assert.deepEqual(
      harness.calls.find(call => call.method === 'verifyCode')?.args,
      [challengeId, '123456', undefined]
    );

    const finalize = await fetch(`${baseUrl}/v1/auth/email-verification/verify-code`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer valid-token'
      },
      body: JSON.stringify({ challengeId, code: '123456' })
    });
    assert.equal(finalize.status, 200);
    assert.deepEqual(harness.verifiedUsers, ['firebase-user-1']);
    assert.deepEqual(
      harness.calls.filter(call => call.method === 'verifyCode').at(-1)?.args,
      [challengeId, '123456', email]
    );
  });
});

test('authenticated finalization cannot bind a verified challenge to another email', async () => {
  const harness = createHarness({
    identity: {
      firebaseUid: 'firebase-user-2',
      claims: { email: 'other@example.com', email_verified: false }
    }
  });
  await withServer(harness.app, async baseUrl => {
    const response = await fetch(`${baseUrl}/v1/auth/email-verification/verify-code`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: 'Bearer valid-token'
      },
      body: JSON.stringify({ challengeId, code: '123456' })
    });
    assert.equal(response.status, 403);
    assert.deepEqual(harness.verifiedUsers, []);
  });
});

test('resending is limited to an active unverified account and invalidates older pending codes', async () => {
  const operations: string[] = [];
  const pool = {
    query: async (sql: string) => {
      operations.push(sql);
      if (sql.startsWith('SELECT id, status, email_verified_at')) {
        return {
          rows: [{ id: 'user-1', status: 'active', email_verified_at: null }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 1 };
    }
  } as unknown as Pool;
  let sent = 0;
  const provider: EmailProvider = {
    send: async message => {
      sent += 1;
      assert.equal(message.to, email);
    }
  };
  const config = loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' });
  const service = new EmailVerificationService(pool, provider, config);

  const challenge = await service.requestCode(email, {
    allowExistingUnverified: true
  });
  assert.ok(challenge.challengeId);
  assert.equal(sent, 1);
  assert.ok(operations.findIndex(sql => sql.startsWith('DELETE FROM email_verification_challenges'))
    < operations.findIndex(sql => sql.startsWith('INSERT INTO email_verification_challenges')));
});

test('an already verified challenge can only be finalized for its matching authenticated email', async () => {
  const code = '123456';
  const digest = createHmac('sha256', testOtpHmacSecret)
    .update(`${challengeId}:${code}`)
    .digest('hex');
  const clientCalls: string[] = [];
  const client = {
    query: async (sql: string) => {
      clientCalls.push(sql);
      if (sql.includes('SELECT id, email, code_digest')) {
        return {
          rows: [{
            id: challengeId,
            email,
            code_digest: digest,
            expires_at: new Date(Date.now() + 60_000),
            attempts: 0,
            max_attempts: 5,
            verified_at: new Date()
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 1 };
    },
    release: () => undefined
  };
  const pool = { connect: async () => client } as unknown as Pool;
  const provider: EmailProvider = { send: async () => undefined };
  const config = loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' });
  const service = new EmailVerificationService(pool, provider, config);

  const result = await service.verifyCode(challengeId, code, email);
  assert.equal(result.verified, true);
  assert.equal(result.email, email);
  assert.ok(clientCalls.includes('COMMIT'));

  await assert.rejects(
    () => service.verifyCode(challengeId, code),
    (error: unknown) => error instanceof AppError && error.code === 'CONFLICT'
  );
  await assert.rejects(
    () => service.verifyCode(challengeId, code, 'other@example.com'),
    (error: unknown) => error instanceof AppError && error.code === 'FORBIDDEN'
  );
});


test('authenticated unprovisioned Firebase signups can recover a verification code', async () => {
  const queries: string[] = [];
  const pool = {
    query: async (sql: string) => {
      queries.push(sql);
      return { rows: [], rowCount: 0 };
    }
  } as unknown as Pool;
  let sent = 0;
  const provider: EmailProvider = { send: async message => {
    sent += 1;
    assert.equal(message.to, email);
  } };
  const config = loadConfig({ NODE_ENV: 'test', LOG_LEVEL: 'silent' });
  const service = new EmailVerificationService(pool, provider, config);

  const challenge = await service.requestCode(email, {
    allowExistingUnverified: true
  });
  assert.ok(challenge.challengeId);
  assert.equal(sent, 1);
  assert.ok(queries.some(sql => sql.includes('SELECT id, status, email_verified_at')));
});
