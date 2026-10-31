import assert from 'node:assert/strict';
import test from 'node:test';
import { VirtualAccountService } from '../src/modules/bank/virtual-account-service.js';

test('dedicated bank account assignment requires explicit consent', async () => {
  const service = new VirtualAccountService({} as never, {} as never, {} as never);
  await assert.rejects(
    () => service.assign('user-1', false),
    /Explicit consent is required/
  );
});

test('DVA webhook rejects deposits in a currency different from the assigned wallet', async () => {
  const account = {
    userId: 'user-1',
    walletId: 'wallet-1',
    provider: 'paystack',
    customerCode: 'CUS_test',
    accountNumber: '0123456789',
    currency: 'NGN',
    status: 'active'
  };
  let released = false;
  const client = {
    query: async () => ({ rows: [account] }),
    release: () => { released = true; }
  };
  const pool = {
    connect: async () => client
  };

  const service = new VirtualAccountService(pool as never, {} as never, {} as never);
  await assert.rejects(
    () => service.handleWebhook('charge.success', {
      reference: 'dva-currency-mismatch-001',
      amount: 1000,
      currency: 'USD',
      customer_code: 'CUS_test',
      dedicated_account: { account_number: '0123456789' }
    }),
    /Virtual account webhook currency does not match/
  );
  assert.equal(released, true);
});
