import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import { PaystackPaymentProvider } from '../src/modules/payments/providers/paystack.js';
import type { AppConfig } from '../src/config/env.js';

const config = {
  PAYSTACK_ENABLED: true,
  PAYSTACK_MODE: 'test',
  PAYSTACK_SECRET_KEY: 'sk_test_example',
  PAYSTACK_WEBHOOK_SECRET: 'whsec_example',
  PAYMENT_CALLBACK_URL: ''
} as AppConfig;

test('Paystack webhook signatures are verified against the raw body', () => {
  const provider = new PaystackPaymentProvider(config);
  const rawBody = JSON.stringify({ event: 'charge.success', data: { reference: 'eazy-1' } });
  const signature = crypto.createHmac('sha512', 'whsec_example').update(rawBody).digest('hex');
  assert.equal(provider.verifyWebhookSignature(rawBody, signature), true);
  assert.equal(provider.verifyWebhookSignature(rawBody, `${signature.slice(0, -1)}0`), false);
  assert.equal(provider.verifyWebhookSignature(`${rawBody} `, signature), false);
});

test('Paystack provider refuses initialization when disabled', async () => {
  const provider = new PaystackPaymentProvider({ ...config, PAYSTACK_ENABLED: false });
  await assert.rejects(() => provider.createPayment({ amount: '100.00', currency: 'NGN', reference: 'eazy-2' }), /not configured/);
  assert.equal(provider.getCapabilities().available, false);
});
