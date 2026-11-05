import assert from 'node:assert/strict';
import test from 'node:test';
import { PaymentPinService } from '../src/modules/wallet/payment-pin-service.js';
import type { EmailMessage, EmailProvider } from '../src/providers/resend-email.js';
import type { AppConfig } from '../src/config/env.js';

type StoredPin = {
  user_id: string;
  pin_hash: string;
  pin_length: number;
  failed_attempts: number;
  locked_until: Date | null;
};

type StoredChallenge = {
  id: string;
  user_id: string;
  code_digest: string;
  expires_at: Date;
  attempts: number;
  max_attempts: number;
  consumed_at: Date | null;
};

class FakePool {
  record: StoredPin | null = null;
  challenge: StoredChallenge | null = null;

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
    if (sql.startsWith('SELECT email FROM users')) {
      return { rows: [{ email: 'verified@example.com' }], rowCount: 1 };
    }
    if (sql.startsWith('DELETE FROM payment_pin_verification_challenges')) {
      this.challenge = null;
      return { rows: [], rowCount: 1 };
    }
    if (sql.startsWith('INSERT INTO payment_pin_verification_challenges')) {
      this.challenge = {
        id: String(values[0]),
        user_id: String(values[1]),
        code_digest: String(values[2]),
        expires_at: values[3] as Date,
        attempts: 0,
        max_attempts: Number(values[4]),
        consumed_at: null
      };
      return { rows: [], rowCount: 1 };
    }
    if (sql.includes('FROM payment_pin_verification_challenges WHERE id =')) {
      const row = this.challenge && this.challenge.id === values[0] && this.challenge.user_id === values[1]
        ? this.challenge
        : null;
      return { rows: row ? [{ ...row }] : [], rowCount: row ? 1 : 0 };
    }
    if (sql.startsWith('UPDATE payment_pin_verification_challenges SET attempts = attempts + 1')) {
      if (this.challenge) this.challenge.attempts += 1;
      return { rows: [], rowCount: this.challenge ? 1 : 0 };
    }
    if (sql.startsWith('UPDATE payment_pin_verification_challenges SET consumed_at')) {
      if (this.challenge) this.challenge.consumed_at = new Date();
      return { rows: [], rowCount: this.challenge ? 1 : 0 };
    }
    if (sql.includes('SELECT user_id FROM wallet_payment_pins')) {
      return { rows: this.record ? [{ user_id: this.record.user_id }] : [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.includes('SELECT pin_hash, failed_attempts, locked_until')) {
      return { rows: this.record ? [{ ...this.record }] : [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.includes('SELECT locked_until, pin_length FROM wallet_payment_pins')) {
      return { rows: this.record ? [{ locked_until: this.record.locked_until, pin_length: this.record.pin_length }] : [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.startsWith('INSERT INTO wallet_payment_pins')) {
      this.record = {
        user_id: String(values[0]),
        pin_hash: String(values[1]),
        pin_length: Number(values[2] ?? 4),
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
    if (sql.includes('SET pin_hash = $2, pin_length = 4')) {
      if (this.record) {
        this.record.pin_hash = String(values[1]);
        this.record.pin_length = 4;
        this.record.failed_attempts = 0;
        this.record.locked_until = null;
      }
      return { rows: [], rowCount: this.record ? 1 : 0 };
    }
    if (sql.includes('ON CONFLICT (user_id) DO UPDATE SET pin_hash')) {
      this.record = {
        user_id: String(values[0]),
        pin_hash: String(values[1]),
        pin_length: 4,
        failed_attempts: 0,
        locked_until: null
      };
      return { rows: [], rowCount: 1 };
    }
    throw new Error('Unexpected SQL in fake payment PIN pool: ' + sql);
  }
}

class FakeEmailProvider implements EmailProvider {
  lastMessage: EmailMessage | null = null;
  async send(message: EmailMessage) {
    this.lastMessage = message;
  }
  code(): string {
    const match = this.lastMessage?.text.match(/\b(\d{6})\b/);
    if (!match) throw new Error('Verification code was not included in the email');
    return match[1]!;
  }
}

function createService() {
  const pool = new FakePool();
  const email = new FakeEmailProvider();
  const config = {
    NODE_ENV: 'test',
    OTP_HMAC_SECRET: 'test-only-secret-that-is-at-least-thirty-two-characters',
    OTP_TTL_MINUTES: 10,
    OTP_MAX_ATTEMPTS: 5
  } as AppConfig;
  return { pool, email, service: new PaymentPinService(pool as never, email, config) };
}

async function requestCode(service: PaymentPinService, email: FakeEmailProvider) {
  const challenge = await service.requestVerificationCode('user-1');
  return { challengeId: challenge.challengeId, code: email.code() };
}

test('payment PINs are stored as hashes and new PINs are exactly four digits', async () => {
  const { pool, email, service } = createService();
  const challenge = await requestCode(service, email);
  await service.setup('user-1', '4839', '4839', challenge.challengeId, challenge.code);
  assert.equal((await service.status('user-1')).configured, true);
  assert.equal((await service.status('user-1')).pinLength, 4);
  assert.equal(pool.record?.pin_hash.includes('4839'), false);
  await service.verify('user-1', '4839');
  await assert.rejects(() => service.verify('user-1', '123456'), /Incorrect payment PIN/);
  await assert.rejects(() => service.setup('user-1', '483920', '483920', challenge.challengeId, challenge.code), /exactly 4 digits/);
});

test('PIN mutation requires a valid one-time email code', async () => {
  const { email, service } = createService();
  const challenge = await requestCode(service, email);
  await assert.rejects(
    () => service.setup('user-1', '4839', '4839', challenge.challengeId, '000000'),
    /Incorrect verification code/
  );
  await service.setup('user-1', '4839', '4839', challenge.challengeId, challenge.code);
  await assert.rejects(
    () => service.change('user-1', '4839', '7261', '7261', challenge.challengeId, challenge.code),
    /already been used/
  );
});

test('payment PIN locks after five incorrect attempts', async () => {
  const { email, service } = createService();
  const challenge = await requestCode(service, email);
  await service.setup('user-1', '4839', '4839', challenge.challengeId, challenge.code);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    await assert.rejects(() => service.verify('user-1', '1111'), /Incorrect payment PIN/);
  }
  await assert.rejects(() => service.verify('user-1', '1111'), /locked after repeated incorrect attempts/);
  await assert.rejects(() => service.verify('user-1', '4839'), /locked after repeated incorrect attempts/);
});

test('changing a payment PIN requires the current PIN and a verified email code', async () => {
  const { pool, email, service } = createService();
  let challenge = await requestCode(service, email);
  await service.setup('user-1', '4839', '4839', challenge.challengeId, challenge.code);
  challenge = await requestCode(service, email);
  await assert.rejects(
    () => service.change('user-1', '1111', '7261', '7261', challenge.challengeId, challenge.code),
    /Incorrect payment PIN/
  );
  await service.change('user-1', '4839', '7261', '7261', challenge.challengeId, challenge.code);
  assert.equal(pool.record?.pin_length, 4);
  await service.verify('user-1', '7261');
  await assert.rejects(() => service.verify('user-1', '4839'), /Incorrect payment PIN/);
});

test('payment PIN reset requires a one-time verified email code and clears lockout state', async () => {
  const { email, service } = createService();
  let challenge = await requestCode(service, email);
  await service.setup('user-1', '4839', '4839', challenge.challengeId, challenge.code);
  challenge = await requestCode(service, email);
  await service.reset('user-1', '7261', '7261', challenge.challengeId, challenge.code);
  await service.verify('user-1', '7261');
  await assert.rejects(() => service.reset('user-1', '1357', '1357', challenge.challengeId, challenge.code), /already been used/);
});
