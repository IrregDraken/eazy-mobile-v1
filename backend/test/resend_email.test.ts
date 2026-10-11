import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../src/config/env.js';
import { ResendEmailProvider } from '../src/providers/resend-email.js';

const base = {
  NODE_ENV: 'production',
  PORT: '3000',
  LOG_LEVEL: 'silent',
  DATABASE_URL: 'postgresql://localhost:5432/eazy',
  SUPABASE_URL: 'https://eazy-test.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'synthetic-test-service-role-key',
  CORS_ORIGIN: 'https://eazy.test',
  ENFORCE_HTTPS: 'true',
  TRUST_PROXY: 'true',
  FIREBASE_PROJECT_ID: 'eazy-production',
  FIREBASE_CLIENT_EMAIL: 'firebase-adminsdk@example.com',
  FIREBASE_PRIVATE_KEY: 'test-private-key',
  RESEND_API_KEY: 're_test_key',
  RESEND_FROM_EMAIL: 'noreply@eazy.name.ng'
} satisfies NodeJS.ProcessEnv;

test('Reply-To must be a valid email address when configured', () => {
  assert.throws(
    () => loadConfig({ ...base, RESEND_REPLY_TO_EMAIL: 'not-an-email' }),
    (error: unknown) => error instanceof Error && error.message.includes('RESEND_REPLY_TO_EMAIL')
  );
});

test('Resend provider sends the configured Reply-To without exposing credentials', async () => {
  const config = loadConfig({ ...base, RESEND_REPLY_TO_EMAIL: 'support@eazy.name.ng' });
  const originalFetch = globalThis.fetch;
  let requestBody: Record<string, unknown> | undefined;
  let requestHeaders: Headers | undefined;
  globalThis.fetch = (async (_input, init) => {
    requestHeaders = new Headers(init?.headers);
    requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return new Response(null, { status: 200 });
  }) as typeof fetch;
  try {
    await new ResendEmailProvider(config).send({
      to: 'person@example.com',
      subject: 'Test',
      text: 'Text',
      html: '<p>Text</p>'
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.equal(requestBody?.from, 'noreply@eazy.name.ng');
  assert.equal(requestBody?.reply_to, 'support@eazy.name.ng');
  assert.deepEqual(requestBody?.to, ['person@example.com']);
  assert.equal(requestHeaders?.get('authorization'), 'Bearer re_test_key');
  assert.equal(JSON.stringify(requestBody).includes('re_test_key'), false);
});

test('Resend provider omits Reply-To when it is not configured', async () => {
  const config = loadConfig(base);
  const originalFetch = globalThis.fetch;
  let requestBody: Record<string, unknown> | undefined;
  globalThis.fetch = (async (_input, init) => {
    requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return new Response(null, { status: 200 });
  }) as typeof fetch;
  try {
    await new ResendEmailProvider(config).send({
      to: 'person@example.com',
      subject: 'Test',
      text: 'Text',
      html: '<p>Text</p>'
    });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.equal(Object.hasOwn(requestBody ?? {}, 'reply_to'), false);
});
