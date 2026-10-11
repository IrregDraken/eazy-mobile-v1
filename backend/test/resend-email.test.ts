import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../src/config/env.js';
import { ResendEmailProvider } from '../src/providers/resend-email.js';

const message = {
  to: 'customer@example.com',
  subject: 'Eazy verification',
  text: 'Your verification code is available in the app.',
  html: '<p>Your verification code is available in the app.</p>'
};

test('Resend provider includes the configured reply-to address', async () => {
  const config = loadConfig({
    NODE_ENV: 'test',
    RESEND_API_KEY: 're_test_key',
    RESEND_FROM_EMAIL: 'no-reply@eazy.name.ng',
    RESEND_REPLY_TO_EMAIL: 'support@eazy.name.ng'
  });
  const originalFetch = globalThis.fetch;
  let sentPayload: Record<string, unknown> | undefined;

  globalThis.fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    sentPayload = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return new Response(JSON.stringify({ id: 'test-email-id' }), {
      status: 200,
      headers: { 'content-type': 'application/json' }
    });
  }) as typeof fetch;

  try {
    await new ResendEmailProvider(config).send(message);
    assert.deepEqual(sentPayload?.reply_to, ['support@eazy.name.ng']);
    assert.equal(sentPayload?.from, 'no-reply@eazy.name.ng');
    assert.deepEqual(sentPayload?.to, ['customer@example.com']);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test('Resend provider omits reply-to when it is not configured', async () => {
  const config = loadConfig({
    NODE_ENV: 'test',
    RESEND_API_KEY: 're_test_key',
    RESEND_FROM_EMAIL: 'no-reply@eazy.name.ng'
  });
  const originalFetch = globalThis.fetch;
  let sentPayload: Record<string, unknown> | undefined;

  globalThis.fetch = (async (_input: string | URL | Request, init?: RequestInit) => {
    sentPayload = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return new Response(JSON.stringify({ id: 'test-email-id' }), {
      status: 200,
      headers: { 'content-type': 'application/json' }
    });
  }) as typeof fetch;

  try {
    await new ResendEmailProvider(config).send(message);
    assert.equal(Object.hasOwn(sentPayload ?? {}, 'reply_to'), false);
  } finally {
    globalThis.fetch = originalFetch;
  }
});
