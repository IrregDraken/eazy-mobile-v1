import assert from 'node:assert/strict';
import test from 'node:test';
import { PaymentPinService } from '../src/modules/wallet/payment-pin-service.js';

type StoredPin = {
  user_id: string;
  pin_hash: string;
  failed_attempts: number;
  locked_until: Date | null;
};

class FakePool {
  record: StoredPin | null = null;

  async connect() {
    return {
      query: async (sql: string, values: unknown[] = []) => this.execute(sql, values),
      release: () => undefined
    };
  }

  async query(sql: string, values: unknown[] = []) {
    return this.execute(sql, values);
  }

  private async execute(sql: string, values: unknown[]) {
    if (sql === 'BEGIN' || sql === 'COMMIT' || sql === 'ROLLBACK' || sql.startsWith('SELECT pg_advisory_xact_lock')) {
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes('SELECT user_id FROM wallet_payment_pins')) {
      return { rows: this.record ? [{ user_id: this.record.user_id }] : [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.includes('SELECT pin_hash, failed_attempts, locked_until')) {
      return { rows: this.record ? [{ ...this.record }] : [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.includes('SELECT locked_until FROM wallet_payment_pins')) {
      return { rows: this.record ? [{ locked_until: this.record.locked_until }] : [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.startsWith('INSERT INTO wallet_payment_pins')) {
      this.record = {
        user_id: String(values[0]),
        pin_hash: String(values[1]),
        failed_attempts: 0,
        locked_until: null
      };
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('SET failed_attempts = $2, locked_until = $3')) {
      if (this.record) {
        this.record.failed_attempts = Number(values[1]);
        this.record.locked_until = values[2] as Date | null;
      }
      return { rows: [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.includes('SET failed_attempts = 0, locked_until = NULL')) {
      if (this.record) {
        this.record.failed_attempts = 0;
        this.record.locked_until = null;
      }
      return { rows: [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.includes('SET pin_hash = $2')) {
      if (this.record) {
        this.record.pin_hash = String(values[1]);
        this.record.failed_attempts = 0;
        this.record.locked_until = null;
      }
      return { rows: [], rowCount: this.record ? 1 : 0 };
    }
    throw new Error('Unexpected SQL in fake payment PIN pool: ' + sql);
  }
}

test('payment PINs are stored as hashes and can be verified', async () => {
  const pool = new FakePool();
  const service = new PaymentPinService(pool as never);
  await service.setup('user-1', '483920', '483920');
  assert.equal((await service.status('user-1')).configured, true);
  assert.equal(pool.record?.pin_hash.includes('483920'), false);
  await service.verify('user-1', '483920');
  await assert.rejects(() => service.verify('user-1', '111111'), /Incorrect payment PIN/);
});

test('payment PIN locks after five incorrect attempts', async () => {
  const pool = new FakePool();
  const service = new PaymentPinService(pool as never);
  await service.setup('user-1', '483920', '483920');
  for (let attempt = 0; attempt < 4; attempt += 1) {
    await assert.rejects(() => service.verify('user-1', '111111'), /Incorrect payment PIN/);
  }
  await assert.rejects(() => service.verify('user-1', '111111'), /locked after repeated incorrect attempts/);
  await assert.rejects(() => service.verify('user-1', '483920'), /locked after repeated incorrect attempts/);
});

test('changing a payment PIN requires the current PIN', async () => {
  const pool = new FakePool();
  const service = new PaymentPinService(pool as never);
  await service.setup('user-1', '483920', '483920');
  await assert.rejects(() => service.change('user-1', '111111', '726194', '726194'), /Incorrect payment PIN/);
  await service.change('user-1', '483920', '726194', '726194');
  await service.verify('user-1', '726194');
  await assert.rejects(() => service.verify('user-1', '483920'), /Incorrect payment PIN/);
});

test('payment PIN reset replaces an existing PIN and clears lockout state', async () => {
  const pool = new FakePool();
  const service = new PaymentPinService(pool as never);
  await service.setup('user-1', '483920', '483920');
  await service.reset('user-1', '726194', '726194');
  await service.verify('user-1', '726194');
  await assert.rejects(() => service.verify('user-1', '483920'), /Incorrect payment PIN/);
});
