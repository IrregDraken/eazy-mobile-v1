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


const originalFetch = globalThis.fetch;
test.afterEach(() => { globalThis.fetch = originalFetch; });

test('Paystack DVA assignment uses profile identity and resolves nested customer code', async () => {
  const requests: { url: string; method: string; body: Record<string, unknown> }[] = [];
  globalThis.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    const method = init?.method ?? 'GET';
    const body = init?.body ? JSON.parse(String(init.body)) as Record<string, unknown> : {};
    requests.push({ url, method, body });
    if (url.endsWith('/customer/user@example.com')) {
      return new Response(JSON.stringify({ status: false, message: 'Customer not found' }), { status: 404 });
    }
    if (url.endsWith('/customer') && method === 'POST') {
      return new Response(JSON.stringify({ status: true, data: { customer_code: 'CUS_eazy_test' } }), { status: 200 });
    }
    if (url.endsWith('/dedicated_account') && method === 'POST') {
      return new Response(JSON.stringify({ status: true, data: {
        customer: { customer_code: 'CUS_eazy_test' },
        account_number: '0123456789',
        account_name: 'EAZY USER',
        bank: { name: 'Test Bank', slug: 'test-bank' },
        active: true,
        assigned: true
      } }), { status: 200 });
    }
    return new Response(JSON.stringify({ status: false, message: 'Unexpected request' }), { status: 500 });
  };

  const provider = new PaystackBankProvider(config);
  const account = await provider.assignVirtualAccount({
    email: 'user@example.com',
    firstName: 'Eazy',
    lastName: 'User',
    phone: '+2348012345678',
    currency: 'NGN'
  });
  assert.equal(account.customerCode, 'CUS_eazy_test');
  assert.equal(account.accountNumber, '0123456789');
  assert.equal(account.status, 'active');
  const assignment = requests.find(request => request.url.endsWith('/dedicated_account'));
  assert.ok(assignment);
  assert.equal(assignment.body.customer, 'CUS_eazy_test');
  assert.equal(assignment.body.preferred_bank, 'test-bank');
  assert.equal('bvn' in assignment.body, false);
  assert.equal('account_number' in assignment.body, false);
  assert.equal('bank_code' in assignment.body, false);
});

test('Paystack does not mark an unassigned or inactive DVA as active', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ status: true, data: {
    customer_code: 'CUS_pending',
    dedicated_account: {
      account_number: '0123456789',
      account_name: 'EAZY USER',
      bank: { name: 'Wema Bank', slug: 'wema-bank' },
      active: false,
      assigned: false
    }
  } }), { status: 200 });
  const provider = new PaystackBankProvider({ ...config, PAYSTACK_MODE: 'live' });
  const account = await provider.getVirtualAccount({ customerCode: 'CUS_pending' });
  assert.equal(account?.status, 'pending');
});


test('Paystack reuses an existing dedicated account after an interrupted activation attempt', async () => {
  const urls: string[] = [];
  globalThis.fetch = async input => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    urls.push(url);
    return new Response(JSON.stringify({ status: true, data: {
      customer_code: 'CUS_existing',
      dedicated_account: {
        account_number: '0123456789',
        account_name: 'EAZY USER',
        bank: { name: 'Wema Bank', slug: 'wema-bank' },
        active: true,
        assigned: true
      }
    } }), { status: 200 });
  };
  const provider = new PaystackBankProvider({ ...config, PAYSTACK_MODE: 'live' });
  const account = await provider.assignVirtualAccount({
    email: 'user@example.com',
    firstName: 'Eazy',
    lastName: 'User',
    phone: '+2348012345678',
    currency: 'NGN'
  });
  assert.equal(account.customerCode, 'CUS_existing');
  assert.equal(account.status, 'active');
  assert.equal(urls.length, 1);
  assert.ok(urls[0]?.endsWith('/customer/user%40example.com'));
});
