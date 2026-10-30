import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import test from 'node:test';
import type { Pool } from 'pg';

import { loadConfig } from '../src/config/env.js';
import { EmailVerificationService } from '../src/modules/auth/email-verification.js';
import type { EmailMessage, EmailProvider } from '../src/providers/resend-email.js';

test('email verification stores and validates keyed HMAC digests', async () => {
  const key = 'x'.repeat(40);
  const email = 'person@example.com';
  let insertedValues: unknown[] | undefined;
  let sentMessage: EmailMessage | undefined;

  const client = {
    query: async (sql: string) => {
      if (sql.startsWith('SELECT id, email, code_digest')) {
        return {
          rows: [{
            id: insertedValues?.[0],
            email,
            code_digest: insertedValues?.[2],
            expires_at: new Date(Date.now() + 10 * 60_000),
            attempts: 0,
            max_attempts: 5,
            verified_at: null
          }],
          rowCount: 1
        };
      }
      return { rows: [], rowCount: 1 };
    },
    release: () => undefined
  };
  const pool = {
    query: async (sql: string, values?: unknown[]) => {
      if (sql.startsWith('SELECT id FROM users')) return { rows: [], rowCount: 0 };
      if (sql.startsWith('INSERT INTO email_verification_challenges')) {
        insertedValues = values;
        return { rows: [], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    },
    connect: async () => client
  } as unknown as Pool;
  const provider: EmailProvider = {
    send: async message => { sentMessage = message; }
  };
  const config = loadConfig({
    NODE_ENV: 'test',
    LOG_LEVEL: 'silent',
    OTP_HMAC_SECRET: key
  });
  const service = new EmailVerificationService(pool, provider, config);

  const challenge = await service.requestCode(email);
  assert.ok(insertedValues);
  assert.ok(sentMessage);
  const code = sentMessage.text.match(/\n(\d{6})\n/)?.[1];
  assert.ok(code);
  const expected = createHmac('sha256', key)
    .update(`${challenge.challengeId}:${code}`)
    .digest('hex');
  assert.equal(insertedValues[2], expected);

  const verified = await service.verifyCode(challenge.challengeId, code);
  assert.equal(verified.verified, true);
  assert.equal(verified.email, email);
});
