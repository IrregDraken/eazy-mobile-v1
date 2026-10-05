import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import test from 'node:test';
import type { RequestHandler } from 'express';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { AppError } from '../src/middleware/errors.js';
import { idempotencyKey } from '../src/middleware/idempotency.js';
import type { DbClient } from '../src/database/client.js';
import { LedgerService } from '../src/modules/ledger/service.js';
import { PaymentService } from '../src/modules/payments/service.js';
import type { PaymentProvider } from '../src/providers/interfaces.js';
import type { PaymentIntentRecord, PaymentRepositoryContract } from '../src/modules/payments/types.js';
import { UnavailablePaymentProvider } from '../src/modules/payments/providers/unavailable.js';
import { QrService } from '../src/modules/qr/service.js';
import type { QrRecord, QrRepositoryContract } from '../src/modules/qr/types.js';
import { qrCreateSchema, qrPaymentSchema } from '../src/modules/qr/schemas.js';
import { amountToMinorUnits, currencySchema, moneyAmountSchema, transferSchema } from '../src/modules/wallet/schemas.js';
import { WalletService } from '../src/modules/wallet/service.js';
import type { TransferRecord, WalletRepositoryContract } from '../src/modules/wallet/types.js';
import { createWalletRouter } from '../src/modules/wallet/routes.js';
import { createPaymentRouter } from '../src/modules/payments/routes.js';
import { createQrRouter } from '../src/modules/qr/routes.js';

const userA = '00000000-0000-4000-8000-000000000001';
const userB = '00000000-0000-4000-8000-000000000002';
const walletA = '10000000-0000-4000-8000-000000000001';
const walletB = '10000000-0000-4000-8000-000000000002';
const txId = '20000000-0000-4000-8000-000000000001';
const orderId = '30000000-0000-4000-8000-000000000001';
const fixedTime = '2026-09-24T20:00:00.000Z';
const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

function minor(value: string): bigint {
  const [whole, cents = ''] = value.split('.');
  return BigInt(whole!) * 100n + BigInt(cents.padEnd(2, '0'));
}
function major(value: bigint): string { return `${value / 100n}.${String(value % 100n).padStart(2, '0')}`; }

interface WalletState {
  balances: Map<string, bigint>;
  wallets: Map<string, { id: string; userId: string; currency: string; status: string }>;
  transfers: Map<string, TransferRecord>;
  ledger: { walletId: string; transactionId: string; direction: string; amount: string; currency: string; idempotencyKey: string }[];
  rollbacks: number;
}

function transactionalPool(initial: WalletState) {
  let committed = structuredClone(initial);
  let rollbackCount = 0;
  let lock: Promise<void> = Promise.resolve();
  const working = new WeakMap<object, WalletState>();
  const pool = {
    connect: async () => {
      const previous = lock;
      let releaseCurrent!: () => void;
      lock = new Promise<void>(resolve => { releaseCurrent = resolve; });
      await previous;
      let work = structuredClone(committed);
      const client = {
        query: async (sql: string) => {
          if (sql === 'BEGIN') { work = structuredClone(committed); working.set(client, work); return { rows: [], rowCount: 0 }; }
          if (sql === 'COMMIT') { committed = structuredClone(work); return { rows: [], rowCount: 0 }; }
          if (sql === 'ROLLBACK') { rollbackCount += 1; return { rows: [], rowCount: 0 }; }
          return { rows: [], rowCount: 0 };
        },
        release: () => releaseCurrent()
      };
      return client;
    }
  };
  return {
    pool: pool as never,
    get state() { const snapshot = structuredClone(committed); snapshot.rollbacks = rollbackCount; return snapshot; },
    forClient(client: unknown) { return working.get(client as object) ?? committed; }
  };
}

function seedWalletState(balanceA: string): WalletState {
  return {
    balances: new Map([[walletA, minor(balanceA)], [walletB, 0n]]),
    wallets: new Map([
      [userA, { id: walletA, userId: userA, currency: 'NGN', status: 'active' }],
      [userB, { id: walletB, userId: userB, currency: 'NGN', status: 'active' }]
    ]),
    transfers: new Map(), ledger: [], rollbacks: 0
  };
}

function walletDependencies(pool: unknown, state: ReturnType<typeof transactionalPool>, options: { failLedgerDirection?: string } = {}) {
  const users = new Map([['recipient', { userId: userB, username: 'recipient', displayName: 'Recipient' }], ['self', { userId: userA, username: 'sender', displayName: 'Sender' }]]);
  const repo: WalletRepositoryContract = {
    listWallets: async ownerId => [...state.state.wallets.values()].filter(wallet => wallet.userId === ownerId).map(wallet => ({ id: wallet.id, currency: wallet.currency, status: wallet.status as 'active', balance: major(state.state.balances.get(wallet.id) ?? 0n) })),
    createOrGetWallet: async (_client, ownerId, currency) => {
      const existing = state.state.wallets.get(ownerId);
      return existing ?? { id: 'new-wallet', userId: ownerId, currency, status: 'active' };
    },
    listTransactions: async () => ({ items: [], total: 0 }),
    getTransaction: async (ownerId, id) => ownerId === userA && id === txId ? { id, type: 'transfer', amount: '0.10', currency: 'NGN', status: 'succeeded', reference: 'safe-ref', createdAt: fixedTime } : null,
    resolveRecipientByUsername: async (_client, username) => users.get(username) ?? null,
    findWalletForUser: async (client, ownerId) => state.forClient(client).wallets.get(ownerId) ?? null,
    lockWallets: async (client, userIds) => userIds.map(id => state.forClient(client).wallets.get(id)).filter((value): value is NonNullable<typeof value> => Boolean(value)),
    getBalance: async (client, id) => major(state.forClient(client).balances.get(id) ?? 0n),
    lockIdempotencyKey: async () => undefined,
    findByIdempotencyKey: async (client, key) => state.forClient(client).transfers.get(key) ?? null,
    findTransferRecipient: async (client, id) => {
      const transaction = [...state.forClient(client).transfers.values()].find(value => value.id === id);
      return transaction?.counterpartyWalletId === walletB ? userB : null;
    },
    createTransfer: async (client, input) => {
      const record: TransferRecord = { id: txId, userId: input.userId, walletId: input.walletId, counterpartyWalletId: input.counterpartyWalletId, type: input.type, status: 'pending', amount: input.amount, currency: input.currency, reference: input.reference, idempotencyKey: input.idempotencyKey, orderId: null, createdAt: fixedTime };
      state.forClient(client).transfers.set(input.idempotencyKey, record);
      return record;
    },
    markTransferFailed: async () => undefined,
    markTransferSucceeded: async (client, id) => {
      const record = [...state.forClient(client).transfers.values()].find(value => value.id === id);
      if (!record || record.status !== 'pending') throw new Error('bad state');
      record.status = 'succeeded';
    },
    getTransferById: async (client, id) => [...state.forClient(client).transfers.values()].find(value => value.id === id) ?? null
  };
  let directionCount = 0;
  const ledger = new LedgerService({
    getBalance: async (client, id) => major(state.forClient(client).balances.get(id) ?? 0n),
    createEntry: async (client, entry) => {
      directionCount++;
      if (options.failLedgerDirection === entry.direction && directionCount > 1) throw new Error('ledger failure');
      const work = state.forClient(client);
      const current = work.balances.get(entry.walletId) ?? 0n;
      const delta = minor(entry.amount) * (entry.direction === 'credit' ? 1n : -1n);
      if (current + delta < 0n) throw new Error('insufficient funds');
      work.balances.set(entry.walletId, current + delta);
      work.ledger.push({ walletId: entry.walletId, transactionId: entry.transactionId, direction: entry.direction, amount: entry.amount, currency: entry.currency, idempotencyKey: entry.idempotencyKey });
    }
  });
  return { service: new WalletService(pool as never, repo, ledger), repo };
}

function fakePaymentPool() {
  return { connect: async () => ({ query: async () => ({ rows: [], rowCount: 0 }), release: () => undefined }) } as never;
}

function intentFixture(overrides: Partial<PaymentIntentRecord> = {}): PaymentIntentRecord {
  return { id: txId, userId: userA, walletId: walletA, type: 'deposit', status: 'pending', amount: '100.10', currency: 'NGN', reference: 'trusted-reference', idempotencyKey: 'hash', orderId: null, providerName: 'test-provider', providerReference: null, attemptId: txId, ...overrides };
}

function paymentRepoFixture(options: { order?: { id: string; status: string; currency: string; totalAmount: string } | null } = {}) {
  const intents = new Map<string, PaymentIntentRecord>();
  const byId = new Map<string, PaymentIntentRecord>();
  const repo: PaymentRepositoryContract = {
    lockIdempotencyKey: async () => undefined,
    findByIdempotencyKey: async (_client, key) => intents.get(key) ?? null,
    findOrderForBuyer: async (_client, id, ownerId) => ownerId === userA && options.order && options.order.id === id ? options.order : null,
    findDepositWallet: async () => ({ id: walletA, status: 'active', currency: 'NGN' }),
    createIntent: async (_client, input) => {
      const intent = intentFixture({ id: input.id, attemptId: input.attemptId, userId: input.userId, walletId: input.walletId, type: input.type, amount: input.amount, currency: input.currency, reference: input.reference, idempotencyKey: input.idempotencyKey, orderId: input.orderId, providerName: input.providerName });
      intents.set(input.idempotencyKey, intent);
      byId.set(intent.id, intent);
      return intent;
    },
    saveProviderReference: async (_client, id, attemptId, reference) => {
      const intent = byId.get(id);
      if (!intent || intent.attemptId !== attemptId || intent.status !== 'pending') return false;
      intent.providerReference = reference;
      return true;
    },
    getByIdForUser: async (ownerId, id) => byId.get(id)?.userId === ownerId ? byId.get(id)! : null
  };
  return { repo, intents, byId };
}

function appWithAuth(options: { walletRouter: ReturnType<typeof createWalletRouter>; qrRouter: ReturnType<typeof createQrRouter>; paymentRouter: ReturnType<typeof createPaymentRouter> }) {
  const auth: RequestHandler = (request, _response, next) => {
    if (request.header('authorization') === 'Bearer test-token') request.auth = { userId: userA, provider: 'test', claims: {} };
    next();
  };
  return createApp(config, createLogger(config), { authMiddleware: auth, ...options });
}

async function withServer(app: ReturnType<typeof appWithAuth>, run: (baseUrl: string) => Promise<void>) {
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
}

test('money schema uses exact decimal strings, accepts trailing zeros, and rejects floating/negative/over-precision values', () => {
  assert.equal(moneyAmountSchema.parse('100.10'), '100.10');
  assert.equal(amountToMinorUnits('100.10'), 10010n);
  assert.equal(amountToMinorUnits('0.01'), 1n);
  assert.throws(() => moneyAmountSchema.parse(100.1));
  assert.throws(() => moneyAmountSchema.parse('100.1'));
  assert.throws(() => moneyAmountSchema.parse('100.100'));
  assert.throws(() => moneyAmountSchema.parse('0.00'));
  assert.throws(() => moneyAmountSchema.parse('-1.00'));
  assert.equal(currencySchema.parse(' ngn '), 'NGN');
  assert.throws(() => currencySchema.parse('NGNN'));
  assert.throws(() => transferSchema.parse({ recipientUsername: 'recipient', amount: '1.00', currency: 'NGN', user_id: userB }));
});

test('wallet projections and transaction history are authenticated-user scoped safe reads', async () => {
  const state = transactionalPool(seedWalletState('5.00'));
  const { service } = walletDependencies(state.pool, state);
  const wallet = await service.getWallets(userA);
  assert.equal(wallet.wallet?.balance, '5.00');
  const list = await service.listTransactions(userA, { page: 1, limit: 20 });
  assert.deepEqual(list.meta, { page: 1, limit: 20, cursor: null, total: 0, pages: 0 });
  assert.equal((await service.getTransaction(userA, txId)).transaction.id, txId);
  await assert.rejects(() => service.getTransaction(userB, txId), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
});

test('wallet transfer is exact, balanced, linked, and returns ledger-authoritative amount', async () => {
  const state = transactionalPool(seedWalletState('1.05'));
  const { service } = walletDependencies(state.pool, state);
  const result = await service.transfer(userA, { recipientUsername: 'recipient', amount: '0.10', currency: 'NGN' }, 'same-key-123');
  assert.equal(result.transaction.status, 'succeeded');
  assert.equal(result.transaction.amount, '0.10');
  assert.equal(result.transaction.createdAt, fixedTime);
  assert.equal(state.state.balances.get(walletA), 95n);
  assert.equal(state.state.balances.get(walletB), 10n);
  assert.equal(state.state.ledger.length, 2);
  assert.deepEqual(state.state.ledger.map(entry => entry.direction).sort(), ['credit', 'debit']);
  assert.equal(state.state.ledger[0]!.transactionId, result.transaction.id);
  assert.equal(result.recipient.username, 'recipient');
});

test('idempotent transfer replay returns the original result without duplicating money', async () => {
  const state = transactionalPool(seedWalletState('5.00'));
  const { service } = walletDependencies(state.pool, state);
  const first = await service.transfer(userA, { recipientUsername: 'recipient', amount: '1.00', currency: 'NGN' }, 'repeat-key-123');
  const second = await service.transfer(userA, { recipientUsername: 'recipient', amount: '1.00', currency: 'NGN' }, 'repeat-key-123');
  assert.equal(second.transaction.id, first.transaction.id);
  assert.equal(state.state.balances.get(walletA), 400n);
  assert.equal(state.state.balances.get(walletB), 100n);
  assert.equal(state.state.ledger.length, 2);
  await assert.rejects(() => service.transfer(userA, { recipientUsername: 'recipient', amount: '2.00', currency: 'NGN' }, 'repeat-key-123'), (error: unknown) => error instanceof AppError && error.code === 'CONFLICT');
});

test('QR payment resolves its recipient under the financial transaction and replay avoids a second debit', async () => {
  const state = transactionalPool(seedWalletState('2.00'));
  const { service } = walletDependencies(state.pool, state);
  const lockModes: boolean[] = [];
  const resolveRecipient = async (_client: DbClient, allowInactive: boolean) => {
    lockModes.push(allowInactive);
    return { userId: userB, username: 'recipient', displayName: 'Recipient' };
  };
  const first = await service.payQr(userA, resolveRecipient, '0.25', 'NGN', 'qr-idem-key-123');
  const replay = await service.payQr(userA, resolveRecipient, '0.25', 'NGN', 'qr-idem-key-123');
  assert.equal(first.transaction.type, 'qr_payment');
  assert.equal(replay.transaction.id, first.transaction.id);
  assert.deepEqual(lockModes, [false, true]);
  assert.equal(state.state.balances.get(walletA), 175n);
  assert.equal(state.state.balances.get(walletB), 25n);
  assert.equal(state.state.ledger.length, 2);
});

test('insufficient funds, self-transfer, and currency mismatch reject without financial writes', async () => {
  const state = transactionalPool(seedWalletState('0.99'));
  const { service } = walletDependencies(state.pool, state);
  await assert.rejects(() => service.transfer(userA, { recipientUsername: 'recipient', amount: '1.00', currency: 'NGN' }, 'insufficient-123'), (error: unknown) => error instanceof AppError && error.code === 'CONFLICT');
  await assert.rejects(() => service.transfer(userA, { recipientUsername: 'self', amount: '0.01', currency: 'NGN' }, 'self-key-123'), (error: unknown) => error instanceof AppError && error.code === 'BAD_REQUEST');
  await assert.rejects(() => service.transfer(userA, { recipientUsername: 'recipient', amount: '0.01', currency: 'USD' }, 'currency-123'), (error: unknown) => error instanceof AppError && error.code === 'BAD_REQUEST');
  assert.equal(state.state.ledger.length, 0);
  assert.equal(state.state.transfers.size, 0);
  assert.equal(state.state.balances.get(walletA), 99n);
});

test('transfer ledger failure rolls back transaction, debit, and any first ledger entry', async () => {
  const state = transactionalPool(seedWalletState('3.00'));
  const { service } = walletDependencies(state.pool, state, { failLedgerDirection: 'credit' });
  await assert.rejects(() => service.transfer(userA, { recipientUsername: 'recipient', amount: '1.00', currency: 'NGN' }, 'rollback-key-123'));
  assert.equal(state.state.balances.get(walletA), 300n);
  assert.equal(state.state.balances.get(walletB), 0n);
  assert.equal(state.state.ledger.length, 0);
  assert.equal(state.state.transfers.size, 0);
  assert.equal(state.state.rollbacks, 1);
});

test('serialized concurrent transfers cannot double-spend the same balance', async () => {
  const state = transactionalPool(seedWalletState('1.00'));
  const { service } = walletDependencies(state.pool, state);
  const results = await Promise.allSettled([
    service.transfer(userA, { recipientUsername: 'recipient', amount: '0.70', currency: 'NGN' }, 'concurrent-a-123'),
    service.transfer(userA, { recipientUsername: 'recipient', amount: '0.70', currency: 'NGN' }, 'concurrent-b-123')
  ]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(results.filter(result => result.status === 'rejected').length, 1);
  assert.equal(state.state.balances.get(walletA), 30n);
  assert.equal(state.state.balances.get(walletB), 70n);
  assert.equal(state.state.ledger.length, 2);
});

test('ledger service emits equal debit and credit legs with transaction-scoped unique keys', async () => {
  const entries: unknown[] = [];
  const ledger = new LedgerService({ getBalance: async () => '0.00', createEntry: async (_client, entry) => { entries.push(entry); } });
  await ledger.recordTransfer({} as never, { transactionId: txId, debitWalletId: walletA, creditWalletId: walletB, amount: '100.10', currency: 'NGN', kind: 'wallet_transfer' });
  assert.equal(entries.length, 2);
  assert.deepEqual(entries.map(entry => (entry as { direction: string }).direction).sort(), ['credit', 'debit']);
  assert.ok(entries.every(entry => (entry as { amount: string }).amount === '100.10'));
  assert.ok(entries.every(entry => (entry as { transactionId: string }).transactionId === txId));
  assert.equal((entries[0] as { idempotencyKey: string }).idempotencyKey, `${txId}:debit`);
});

test('QR creation stores only a SHA-256 hash and returns an opaque token with no balance/credentials', async () => {
  let storedHash = '';
  let storedOwner = '';
  const repo: QrRepositoryContract = {
    create: async (_client, input) => { storedHash = input.codeHash; storedOwner = input.ownerId; return { id: txId, createdAt: fixedTime }; },
    resolve: async codeHash => codeHash === storedHash ? { id: txId, ownerId: userA, username: 'sender', displayName: 'Sender', status: 'active', expiresAt: fixedTime } : null,
    resolveForPayment: async (_client, hash) => hash === storedHash ? { id: txId, ownerId: userA, username: 'sender', displayName: 'Sender', status: 'active', expiresAt: fixedTime } : null,
    revoke: async (owner, id) => owner === userA && id === txId
  };
  const qrService = new QrService(fakePaymentPool(), repo);
  const result = await qrService.create(userA, 30);
  const token = result.qr.content;
  assert.equal(token.length, 43);
  assert.equal(storedHash, createHash('sha256').update(token).digest('hex'));
  assert.equal(storedOwner, userA);
  assert.equal(result.qr.expiresAt > fixedTime, true);
  assert.equal(JSON.stringify(result).includes('balance'), false);
  assert.equal(JSON.stringify(result).includes('firebase'), false);
  assert.deepEqual(await qrService.resolve(token), { recipient: { username: 'sender', displayName: 'Sender' } });
  assert.deepEqual(await qrService.revoke(userA, txId), { revoked: true });
  await assert.rejects(() => qrService.revoke(userB, txId), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
  const ineligibleOwnerRepo: QrRepositoryContract = { ...repo, create: async () => null };
  await assert.rejects(() => new QrService(fakePaymentPool(), ineligibleOwnerRepo).create(userB, 30), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
});

test('QR schemas restrict expiry, amount, currency, and reject client recipient/status claims', () => {
  assert.deepEqual(qrCreateSchema.parse({}), { expiresInDays: 30 });
  assert.throws(() => qrCreateSchema.parse({ expiresInDays: 91 }));
  assert.deepEqual(qrPaymentSchema.parse({ token: 'a'.repeat(43), amount: '1.00', currency: 'NGN' }), { token: 'a'.repeat(43), amount: '1.00', currency: 'NGN' });
  assert.throws(() => qrPaymentSchema.parse({ token: 'a'.repeat(43), amount: '1.00', currency: 'NGN', recipientId: userB }));
  assert.throws(() => qrPaymentSchema.parse({ token: 'a'.repeat(43), amount: '1.00', currency: 'NGN', status: 'succeeded' }));
});

test('unavailable payment provider reports false capabilities and never persists or returns success', async () => {
  let createCalls = 0;
  const repo: PaymentRepositoryContract = {
    lockIdempotencyKey: async () => undefined,
    findByIdempotencyKey: async () => null,
    findOrderForBuyer: async () => null,
    findDepositWallet: async () => null,
    createIntent: async () => { createCalls++; return intentFixture(); },
    saveProviderReference: async () => false,
    getByIdForUser: async () => null
  };
  const service = new PaymentService(fakePaymentPool(), new UnavailablePaymentProvider(), repo);
  assert.deepEqual(service.capabilities(), { providerAvailable: false, providerName: null, verificationAvailable: false });
  await assert.rejects(() => service.initialize(userA, { purpose: 'wallet_deposit', amount: '100.00', currency: 'NGN' }, 'unavailable-key-123'), (error: unknown) => error instanceof AppError && error.statusCode === 503);
  assert.equal(createCalls, 0);
  await assert.rejects(() => service.verify(userA, txId), (error: unknown) => error instanceof AppError && error.statusCode === 404);
});

test('payment test adapter initializes a pending provider intent once and reuses it idempotently', async () => {
  const { repo } = paymentRepoFixture();
  let calls = 0;
  const provider: PaymentProvider = { getCapabilities: () => ({ available: true, providerName: 'test-provider' }), createPayment: async input => { calls++; assert.equal(input.amount, '100.10'); assert.equal(input.currency, 'NGN'); return { providerReference: 'provider-reference-test' }; } };
  const service = new PaymentService(fakePaymentPool(), provider, repo);
  const input = { purpose: 'wallet_deposit' as const, amount: '100.10', currency: 'NGN' };
  const first = await service.initialize(userA, input, 'provider-idem-key-123');
  const second = await service.initialize(userA, input, 'provider-idem-key-123');
  assert.equal(first.transaction.status, 'pending');
  assert.equal(first.transaction.amount, '100.10');
  assert.equal(second.transaction.id, first.transaction.id);
  assert.equal(calls, 1);
  assert.equal(first.payment.providerReference, 'provider-reference-test');
  assert.equal(JSON.stringify(await service.get(userA, first.transaction.id)).includes('providerReference'), false);
  await assert.rejects(() => service.get(userB, first.transaction.id), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
  await assert.rejects(() => service.initialize(userA, { purpose: 'wallet_deposit', amount: '100.11', currency: 'NGN' }, 'provider-idem-key-123'), (error: unknown) => error instanceof AppError && error.statusCode === 409);
  await assert.rejects(() => service.verify(userA, first.transaction.id), (error: unknown) => error instanceof AppError && error.statusCode === 503);
  assert.equal(calls, 1);
});

test('order purchase uses database order total/currency and has no client-controlled amount fields', async () => {
  const { repo } = paymentRepoFixture({ order: { id: orderId, status: 'pending', currency: 'NGN', totalAmount: '999.90' } });
  let providerAmount = '';
  let providerCurrency = '';
  const provider: PaymentProvider = { getCapabilities: () => ({ available: true, providerName: 'test-provider' }), createPayment: async input => { providerAmount = input.amount; providerCurrency = input.currency; return { providerReference: 'order-ref' }; } };
  const service = new PaymentService(fakePaymentPool(), provider, repo);
  const result = await service.initialize(userA, { purpose: 'order_purchase', orderId }, 'order-idem-key-123');
  assert.equal(providerAmount, '999.90');
  assert.equal(providerCurrency, 'NGN');
  assert.equal(result.transaction.orderId, orderId);
  assert.equal(result.transaction.status, 'pending');
});

test('ambiguous provider timeout leaves intent pending and idempotency prevents a second possible charge', async () => {
  const { repo } = paymentRepoFixture();
  let calls = 0;
  const provider: PaymentProvider = { getCapabilities: () => ({ available: true, providerName: 'test-provider' }), createPayment: async () => { calls++; throw new Error('timeout after possible acceptance'); } };
  const service = new PaymentService(fakePaymentPool(), provider, repo);
  const input = { purpose: 'wallet_deposit' as const, amount: '1.00', currency: 'NGN' };
  await assert.rejects(() => service.initialize(userA, input, 'timeout-idem-key-123'), (error: unknown) => error instanceof AppError && error.statusCode === 503);
  await assert.rejects(() => service.initialize(userA, input, 'timeout-idem-key-123'), (error: unknown) => error instanceof AppError && error.statusCode === 409);
  assert.equal(calls, 1);
});

test('QR/payment/wallet requests require authentication, reject forged money state, and do not expose fake ledger routes', async () => {
  const state = transactionalPool(seedWalletState('1.00'));
  const { service: walletService } = walletDependencies(state.pool, state);
  const qrRepo: QrRepositoryContract = { create: async () => ({ id: txId, createdAt: fixedTime }), resolve: async () => null, resolveForPayment: async () => null, revoke: async () => false };
  const qrService = new QrService(fakePaymentPool(), qrRepo);
  const paymentRepo = paymentRepoFixture().repo;
  const paymentService = new PaymentService(fakePaymentPool(), new UnavailablePaymentProvider(), paymentRepo);
  const app = appWithAuth({ walletRouter: createWalletRouter(walletService), qrRouter: createQrRouter(qrService, walletService), paymentRouter: createPaymentRouter(paymentService) });
  await withServer(app, async baseUrl => {
    assert.equal((await fetch(`${baseUrl}/v1/wallet`)).status, 401);
    assert.equal((await fetch(`${baseUrl}/v1/payments/capabilities`)).status, 401);
    assert.equal((await fetch(`${baseUrl}/v1/wallet/qr/resolve`, { method: 'POST', body: JSON.stringify({ token: 'x'.repeat(43) }) })).status, 401);
    const headers = { authorization: 'Bearer test-token', 'content-type': 'application/json' };
    assert.equal((await fetch(`${baseUrl}/v1/wallet/transfers`, { method: 'POST', headers, body: JSON.stringify({ recipientUsername: 'recipient', amount: '1.00', currency: 'NGN' }) })).status, 422);
    assert.equal((await fetch(`${baseUrl}/v1/wallet/transfers`, { method: 'POST', headers: { ...headers, 'idempotency-key': 'valid-transfer-123' }, body: JSON.stringify({ recipientUsername: 'recipient', amount: '1.00', currency: 'NGN', userId: userB, balance: '100.00' }) })).status, 422);
    assert.equal((await fetch(`${baseUrl}/v1/payments/initialize`, { method: 'POST', headers: { ...headers, 'idempotency-key': 'valid-payment-123' }, body: JSON.stringify({ purpose: 'wallet_deposit', amount: '1.00', currency: 'NGN', status: 'succeeded' }) })).status, 422);
    assert.equal((await fetch(`${baseUrl}/v1/payments/initialize`, { method: 'POST', headers: { ...headers, 'idempotency-key': 'valid-payment-456' }, body: JSON.stringify({ purpose: 'wallet_deposit', amount: '1.00', currency: 'NGN' }) })).status, 503);
    assert.equal((await fetch(`${baseUrl}/v1/wallet/qr/pay`, { method: 'POST', headers, body: JSON.stringify({ token: 'x'.repeat(43), amount: '1.00', currency: 'NGN', status: 'succeeded' }) })).status, 422);
    assert.equal((await fetch(`${baseUrl}/v1/ledger`, { headers })).status, 404);
  });
});

test('idempotency headers are validated and QR tokens are restricted to opaque base64url-like content', () => {
  assert.throws(() => idempotencyKey({ header: () => undefined } as never), (error: unknown) => error instanceof AppError && error.code === 'VALIDATION_ERROR');
  assert.throws(() => qrPaymentSchema.parse({ token: 'contains spaces and sensitive values '.repeat(2), amount: '1.00', currency: 'NGN' }));
});
