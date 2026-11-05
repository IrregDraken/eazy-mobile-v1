import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import test from 'node:test';
import { PaystackPaymentProvider } from '../src/modules/payments/providers/paystack.js';
import { PaystackBankProvider } from '../src/modules/bank/providers/paystack.js';
import { PaymentRepository } from '../src/modules/payments/repository.js';
import type { AppConfig } from '../src/config/env.js';

const config = {
  PAYSTACK_ENABLED: true,
  PAYSTACK_MODE: 'test',
  PAYSTACK_SECRET_KEY: 'sk_test_example',
  PAYSTACK_WEBHOOK_SECRET: 'whsec_example',
  PAYMENT_CALLBACK_URL: ''
} as AppConfig;

test('Paystack payment and bank webhooks use the account secret key and raw body', () => {
  const provider = new PaystackPaymentProvider(config);
  const bankProvider = new PaystackBankProvider(config);
  const rawBody = JSON.stringify({ event: 'charge.success', data: { reference: 'eazy-1' } });
  const signature = crypto.createHmac('sha512', 'sk_test_example').update(rawBody).digest('hex');
  const wrongKeySignature = crypto.createHmac('sha512', 'whsec_example').update(rawBody).digest('hex');
  assert.equal(provider.verifyWebhookSignature(rawBody, signature), true);
  assert.equal(bankProvider.verifyWebhookSignature(rawBody, signature), true);
  assert.equal(provider.verifyWebhookSignature(rawBody, wrongKeySignature), false);
  assert.equal(bankProvider.verifyWebhookSignature(rawBody, wrongKeySignature), false);
  assert.equal(provider.verifyWebhookSignature(rawBody, `${signature.slice(0, -1)}0`), false);
  assert.equal(provider.verifyWebhookSignature(`${rawBody} `, signature), false);
});

test('Paystack provider refuses initialization when disabled', async () => {
  const provider = new PaystackPaymentProvider({ ...config, PAYSTACK_ENABLED: false });
  await assert.rejects(() => provider.createPayment({ amount: '100.00', currency: 'NGN', reference: 'eazy-2' }), /not configured/);
  assert.equal(provider.getCapabilities().available, false);
});

test('verified order payment writes seller escrow holds in integer kobo exactly once', async () => {
  const calls: { sql: string; values: unknown[] }[] = [];
  const client = {
    query: async (sql: string, values: unknown[] = []) => {
      calls.push({ sql, values });
      if (sql.includes('FROM transactions WHERE id = $1 FOR UPDATE')) {
        return { rows: [{ user_id: 'buyer-id', wallet_id: null, type: 'purchase', order_id: 'order-id', amount: '1500.00', currency: 'NGN', status: 'pending' }], rowCount: 1 };
      }
      if (sql.includes("UPDATE orders SET status = 'paid'")) {
        return { rows: [{ buyer_id: 'buyer-id' }], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    }
  };
  const repository = new PaymentRepository({} as never);
  const settled = await repository.settleProviderPayment(client as never, 'transaction-id', 'paystack-ref', '1500.00', 'NGN');
  assert.equal(settled, true);
  const hold = calls.find(call => call.sql.includes('INSERT INTO seller_payable_ledger'));
  assert.ok(hold);
  assert.match(hold.sql, /amount_kobo/);
  assert.match(hold.sql, /delivery_fee_kobo/);
  assert.deepEqual(hold.values, ['order-id']);
  assert.equal(calls.filter(call => call.sql.includes('INSERT INTO seller_payable_ledger')).length, 1);
});
