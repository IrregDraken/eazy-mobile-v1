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

test('fresh wallet activation reaches the provider and publishes one idempotent result notification', async () => {
  const consentedAt = '2026-11-05T12:00:00.000Z';
  const pending = {
    userId: 'user-test-2', walletId: 'wallet-test-2', provider: 'paystack',
    customerCode: null, accountId: null, accountNumber: null, accountName: null,
    bankName: null, bankSlug: null, currency: 'NGN', status: 'pending',
    consentedAt, failureReason: null, providerEmail: 'member@example.test'
  };
  const active = {
    ...pending, customerCode: 'CUS_TEST_2', accountId: 'DVA_TEST_2',
    accountNumber: 'ACCOUNT_TEST', accountName: 'Test Member',
    bankName: 'Test Bank', status: 'active'
  };
  let storedAccount: typeof pending | typeof active | null = null;
  let providerAssignments = 0;
  let publishedNotifications = 0;
  let notificationEventClaimed = false;

  const client = {
    query: async (sql: string) => {
      if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK') {
        return { rows: [], rowCount: 0 };
      }
      if (sql.includes('SELECT id, status, trim(currency) AS currency FROM wallets')) {
        return { rows: [{ id: 'wallet-test-2', status: 'active', currency: 'NGN' }], rowCount: 1 };
      }
      if (sql.includes('INSERT INTO wallet_virtual_accounts')) {
        storedAccount = pending;
        return { rows: [pending], rowCount: 1 };
      }
      if (sql.includes('UPDATE wallet_virtual_accounts SET')) {
        storedAccount = active;
        return { rows: [active], rowCount: 1 };
      }
      if (sql.includes('INSERT INTO wallet_activation_notification_events')) {
        if (notificationEventClaimed) return { rows: [], rowCount: 0 };
        notificationEventClaimed = true;
        return { rows: [{ user_id: 'user-test-2' }], rowCount: 1 };
      }
      if (sql.includes('UPDATE wallet_activation_notification_events')) {
        return { rows: [], rowCount: 0 };
      }
      throw new Error('Unexpected transaction query');
    },
    release: () => {}
  };

  const pool = {
    query: async (sql: string) => {
      if (sql.includes('SELECT u.email, u.phone, p.display_name')) {
        return {
          rows: [{ email: 'member@example.test', phone: '+19995550123', displayName: 'Test Member' }],
          rowCount: 1
        };
      }
      if (sql.includes('FROM wallet_virtual_accounts WHERE user_id')) {
        return { rows: storedAccount ? [storedAccount] : [], rowCount: storedAccount ? 1 : 0 };
      }
      throw new Error('Unexpected pool query');
    },
    connect: async () => client
  };

  const provider = {
    getCapabilities: () => ({
      available: true, supportsVirtualAccounts: true, providerName: 'paystack'
    }),
    assignVirtualAccount: async () => {
      providerAssignments++;
      return {
        customerCode: 'CUS_TEST_2',
        accountId: 'DVA_TEST_2',
        accountNumber: 'ACCOUNT_TEST',
        accountName: 'Test Member',
        bankName: 'Test Bank',
        status: 'active' as const
      };
    }
  };
  const notifications = {
    createInTransaction: async () => 'notification-test-2',
    publishCreated: async () => { publishedNotifications++; }
  };

  const service = new VirtualAccountService(
    pool as never, provider as never, {} as never, notifications as never
  );
  const assignment = await service.assign('user-test-2', {
    consent: true,
    firstName: 'Test',
    lastName: 'Member',
    phone: '+19995550123',
    preferredBank: 'TEST_BANK',
    country: 'NG',
    accountNumber: 'ACCOUNT_TEST',
    bvn: 'BVN_TEST_01',
    bankCode: 'TEST'
  });

  assert.equal(providerAssignments, 1);
  assert.equal((assignment.virtualAccount as { status: string }).status, 'active');
  assert.equal(publishedNotifications, 1);
  await service.get('user-test-2');
  assert.equal(publishedNotifications, 1);
});
