import { randomBytes, scryptSync, timingSafeEqual } from 'node:crypto';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';

const PIN_PATTERN = /^\d{6}$/;
const MAX_ATTEMPTS = 5;
const LOCK_MINUTES = 15;
const SCRYPT_COST = 16_384;

type PinRecord = {
  pin_hash: string;
  failed_attempts: number;
  locked_until: Date | string | null;
};

export class PaymentPinService {
  constructor(private readonly pool: Pool) {}

  async status(userId: string) {
    const result = await this.pool.query<{ locked_until: Date | string | null }>(
      'SELECT locked_until FROM wallet_payment_pins WHERE user_id = $1',
      [userId]
    );
    return {
      configured: result.rowCount === 1,
      lockedUntil: result.rows[0]?.locked_until ?? null
    };
  }

  async setup(userId: string, pin: string, confirmation: string) {
    this.validatePin(pin);
    if (pin !== confirmation) throw new AppError('VALIDATION_ERROR', 'The payment PINs do not match');
    const pinHash = this.hashPin(pin);
    await withTransaction(this.pool, async client => {
      const existing = await client.query(
        'SELECT user_id FROM wallet_payment_pins WHERE user_id = $1 FOR UPDATE',
        [userId]
      );
      if (existing.rowCount) {
        throw new AppError('CONFLICT', 'A payment PIN already exists. Change your existing PIN instead.');
      }
      await client.query(
        'INSERT INTO wallet_payment_pins (user_id, pin_hash) VALUES ($1, $2)',
        [userId, pinHash]
      );
    });
    return { configured: true };
  }

  async change(userId: string, currentPin: string, newPin: string, confirmation: string) {
    this.validatePin(newPin);
    if (newPin !== confirmation) throw new AppError('VALIDATION_ERROR', 'The new payment PINs do not match');
    if (currentPin === newPin) throw new AppError('VALIDATION_ERROR', 'Choose a different payment PIN');
    await this.verify(userId, currentPin);
    const pinHash = this.hashPin(newPin);
    await this.pool.query(
      'UPDATE wallet_payment_pins SET pin_hash = $2, failed_attempts = 0, locked_until = NULL, updated_at = now() WHERE user_id = $1',
      [userId, pinHash]
    );
    return { changed: true };
  }

  async verify(userId: string, pin: string): Promise<void> {
    this.validatePin(pin);
    const result = await withTransaction(this.pool, async client => {
      const query = await client.query<PinRecord>(
        'SELECT pin_hash, failed_attempts, locked_until FROM wallet_payment_pins WHERE user_id = $1 FOR UPDATE',
        [userId]
      );
      const record = query.rows[0];
      if (!record) return { valid: false as const, reason: 'missing' as const };
      if (record.locked_until && new Date(record.locked_until).getTime() > Date.now()) {
        return { valid: false as const, reason: 'locked' as const };
      }
      if (!this.matchesPin(pin, record.pin_hash)) {
        const attempts = record.failed_attempts + 1;
        const lockedUntil = attempts >= MAX_ATTEMPTS ? new Date(Date.now() + LOCK_MINUTES * 60_000) : null;
        await client.query(
          'UPDATE wallet_payment_pins SET failed_attempts = $2, locked_until = $3, updated_at = now() WHERE user_id = $1',
          [userId, attempts, lockedUntil]
        );
        return { valid: false as const, reason: attempts >= MAX_ATTEMPTS ? 'locked' as const : 'incorrect' as const };
      }
      await client.query(
        'UPDATE wallet_payment_pins SET failed_attempts = 0, locked_until = NULL, updated_at = now() WHERE user_id = $1',
        [userId]
      );
      return { valid: true as const };
    });

    if (result.valid) return;
    if (result.reason === 'missing') {
      throw new AppError('CONFLICT', 'Create a payment PIN in Wallet settings before making this payment');
    }
    if (result.reason === 'locked') {
      throw new AppError('RATE_LIMITED', 'Payment PIN is locked after repeated incorrect attempts. Try again in 15 minutes.');
    }
    throw new AppError('UNAUTHORIZED', 'Incorrect payment PIN');
  }

  private validatePin(pin: string) {
    if (!PIN_PATTERN.test(pin)) throw new AppError('VALIDATION_ERROR', 'Payment PIN must contain exactly 6 digits');
  }

  private hashPin(pin: string) {
    const salt = randomBytes(16);
    const digest = scryptSync(pin, salt, 64, { N: SCRYPT_COST, r: 8, p: 1 });
    return 'scrypt$' + SCRYPT_COST + '$8$1$' + salt.toString('hex') + '$' + digest.toString('hex');
  }

  private matchesPin(pin: string, stored: string) {
    const parts = stored.split('$');
    if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
    const cost = Number(parts[1]);
    const blockSize = Number(parts[2]);
    const parallelization = Number(parts[3]);
    if (cost !== SCRYPT_COST || blockSize !== 8 || parallelization !== 1) return false;
    const salt = Buffer.from(parts[4]!, 'hex');
    const expected = Buffer.from(parts[5]!, 'hex');
    if (salt.length !== 16 || expected.length !== 64) return false;
    const actual = scryptSync(pin, salt, 64, { N: cost, r: blockSize, p: parallelization });
    return timingSafeEqual(actual, expected);
  }
}
