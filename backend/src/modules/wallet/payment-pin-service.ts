import { createHmac, randomBytes, randomInt, randomUUID, scryptSync, timingSafeEqual } from 'node:crypto';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { EmailProvider } from '../../providers/resend-email.js';
import type { AppConfig } from '../../config/env.js';

const NEW_PIN_PATTERN = /^\d{4}$/;
const EXISTING_PIN_PATTERN = /^(?:\d{4}|\d{6})$/;
const MAX_ATTEMPTS = 5;
const LOCK_MINUTES = 15;
const SCRYPT_COST = 16_384;

type PinRecord = {
  pin_hash: string;
  failed_attempts: number;
  locked_until: Date | string | null;
};

export class PaymentPinService {
  constructor(
    private readonly pool: Pool,
    private readonly emailProvider?: EmailProvider,
    private readonly config?: AppConfig,
  ) {}

  async status(userId: string) {
    const result = await this.pool.query<{ locked_until: Date | string | null; pin_length: number }>(
      'SELECT locked_until, pin_length FROM wallet_payment_pins WHERE user_id = $1',
      [userId]
    );
    return {
      configured: result.rowCount === 1,
      pinLength: result.rows[0]?.pin_length ?? null,
      lockedUntil: result.rows[0]?.locked_until ?? null
    };
  }

  async requestVerificationCode(userId: string) {
    if (!this.emailProvider || !this.config) {
      throw new AppError('SERVICE_UNAVAILABLE', 'Payment PIN verification email is not configured');
    }
    const secret = this.config.OTP_HMAC_SECRET;
    if (!secret || secret.length < 32) {
      throw new AppError('SERVICE_UNAVAILABLE', 'Payment PIN verification security is not configured');
    }
    const account = await this.pool.query<{ email: string }>(
      'SELECT email FROM users WHERE id = $1 AND email IS NOT NULL AND email_verified_at IS NOT NULL AND status = \'active\' LIMIT 1',
      [userId]
    );
    const email = account.rows[0]?.email;
    if (!email) throw new AppError('CONFLICT', 'Verify an email address on your Eazy account before managing your payment PIN');
    const ttlMinutes = this.config.OTP_TTL_MINUTES ?? 10;
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const challengeId = randomUUID();
    const expiresAt = new Date(Date.now() + ttlMinutes * 60_000);
    const digest = this.hashVerificationCode(challengeId, userId, code, secret);
    await this.pool.query(
      'DELETE FROM payment_pin_verification_challenges WHERE user_id = $1 AND (expires_at <= now() OR consumed_at IS NOT NULL)',
      [userId]
    );
    await this.pool.query(
      'INSERT INTO payment_pin_verification_challenges (id, user_id, code_digest, expires_at, max_attempts) VALUES ($1, $2, $3, $4, $5)',
      [challengeId, userId, digest, expiresAt, this.config.OTP_MAX_ATTEMPTS ?? 5]
    );
    try {
      await this.emailProvider.send({
        to: email,
        subject: 'Your Eazy payment PIN verification code',
        text: [
          'Eazy payment PIN security',
          '',
          'Use this 6-digit code to create, change or reset your payment PIN:',
          '',
          code,
          '',
          `This code expires in ${ttlMinutes} minutes.`,
          'Never share this code or your payment PIN with anyone.',
          'If you did not request this, ignore this email and secure your account.',
          '',
          'Eazy | Your world, made easier.'
        ].join('\\n'),
        html: `<div style="font-family:Arial,sans-serif;max-width:520px;margin:auto;padding:24px;color:#14241b"><h2>Eazy payment PIN verification</h2><p>Use this code to continue managing your payment PIN:</p><div style="font-size:34px;font-weight:800;letter-spacing:8px;padding:20px;background:#f2f8ec;border-radius:12px;text-align:center">${code}</div><p>This code expires in ${ttlMinutes} minutes. Never share this code or your payment PIN with anyone.</p><p>If you did not request this, ignore this email and secure your account.</p><p>Eazy | Your world, made easier.</p></div>`
      });
    } catch (error) {
      await this.pool.query('DELETE FROM payment_pin_verification_challenges WHERE id = $1', [challengeId]);
      throw error;
    }
    return { challengeId, expiresInSeconds: ttlMinutes * 60 };
  }

  async setup(userId: string, pin: string, confirmation: string, challengeId: string, code: string) {
    this.validateNewPin(pin);
    if (pin !== confirmation) throw new AppError('VALIDATION_ERROR', 'The payment PINs do not match');
    await this.consumeVerificationCode(userId, challengeId, code);
    const pinHash = this.hashPin(pin);
    await withTransaction(this.pool, async client => {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', ['wallet-payment-pin:' + userId]);
      const existing = await client.query(
        'SELECT user_id FROM wallet_payment_pins WHERE user_id = $1 FOR UPDATE',
        [userId]
      );
      if (existing.rowCount) {
        throw new AppError('CONFLICT', 'A payment PIN already exists. Change your existing PIN instead.');
      }
      await client.query(
        'INSERT INTO wallet_payment_pins (user_id, pin_hash, pin_length) VALUES ($1, $2, 4)',
        [userId, pinHash]
      );
    });
    return { configured: true, pinLength: 4 };
  }

  async change(userId: string, currentPin: string, newPin: string, confirmation: string, challengeId: string, code: string) {
    this.validateNewPin(newPin);
    this.validateExistingPin(currentPin);
    if (newPin !== confirmation) throw new AppError('VALIDATION_ERROR', 'The new payment PINs do not match');
    if (currentPin === newPin) throw new AppError('VALIDATION_ERROR', 'Choose a different payment PIN');
    await this.verify(userId, currentPin);
    await this.consumeVerificationCode(userId, challengeId, code);
    const pinHash = this.hashPin(newPin);
    const updated = await this.pool.query(
      'UPDATE wallet_payment_pins SET pin_hash = $2, pin_length = 4, failed_attempts = 0, locked_until = NULL, updated_at = now() WHERE user_id = $1',
      [userId, pinHash]
    );
    if (updated.rowCount !== 1) {
      throw new AppError('CONFLICT', 'Payment PIN changed while this request was being processed. Try again.');
    }
    return { changed: true, pinLength: 4 };
  }

  async reset(userId: string, newPin: string, confirmation: string, challengeId: string, code: string) {
    this.validateNewPin(newPin);
    if (newPin !== confirmation) throw new AppError('VALIDATION_ERROR', 'The new payment PINs do not match');
    await this.consumeVerificationCode(userId, challengeId, code);
    const pinHash = this.hashPin(newPin);
    await this.pool.query(
      'INSERT INTO wallet_payment_pins (user_id, pin_hash, pin_length, failed_attempts, locked_until) VALUES ($1, $2, 4, 0, NULL) ON CONFLICT (user_id) DO UPDATE SET pin_hash = EXCLUDED.pin_hash, pin_length = 4, failed_attempts = 0, locked_until = NULL, updated_at = now()',
      [userId, pinHash]
    );
    return { reset: true, pinLength: 4 };
  }

  async verify(userId: string, pin: string): Promise<void> {
    this.validateExistingPin(pin);
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

  private async consumeVerificationCode(userId: string, challengeId: string, codeInput: string) {
    if (!this.config?.OTP_HMAC_SECRET || this.config.OTP_HMAC_SECRET.length < 32) {
      throw new AppError('SERVICE_UNAVAILABLE', 'Payment PIN verification security is not configured');
    }
    const code = codeInput.trim();
    if (!/^\d{6}$/.test(code)) throw new AppError('VALIDATION_ERROR', 'Verification code must contain 6 digits');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query<{
        id: string; user_id: string; code_digest: string; expires_at: Date | string;
        attempts: number; max_attempts: number; consumed_at: Date | string | null;
      }>(
        'SELECT id, user_id, code_digest, expires_at, attempts, max_attempts, consumed_at FROM payment_pin_verification_challenges WHERE id = $1 AND user_id = $2 FOR UPDATE',
        [challengeId, userId]
      );
      const challenge = result.rows[0];
      if (!challenge) throw new AppError('NOT_FOUND', 'Payment PIN verification request not found');
      if (challenge.consumed_at) throw new AppError('CONFLICT', 'This verification code has already been used');
      if (new Date(challenge.expires_at).getTime() <= Date.now()) throw new AppError('VALIDATION_ERROR', 'Verification code has expired');
      if (challenge.attempts >= challenge.max_attempts) throw new AppError('RATE_LIMITED', 'Too many verification attempts. Request a new code.');
      const actual = Buffer.from(this.hashVerificationCode(challenge.id, userId, code, this.config.OTP_HMAC_SECRET), 'hex');
      const stored = Buffer.from(challenge.code_digest, 'hex');
      const valid = actual.length === stored.length && timingSafeEqual(actual, stored);
      if (!valid) {
        await client.query('UPDATE payment_pin_verification_challenges SET attempts = attempts + 1 WHERE id = $1', [challenge.id]);
        await client.query('COMMIT');
        throw new AppError('UNAUTHORIZED', 'Incorrect verification code');
      }
      await client.query('UPDATE payment_pin_verification_challenges SET consumed_at = now() WHERE id = $1', [challenge.id]);
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  private validateNewPin(pin: string) {
    if (!NEW_PIN_PATTERN.test(pin)) throw new AppError('VALIDATION_ERROR', 'Payment PIN must contain exactly 4 digits');
  }

  private validateExistingPin(pin: string) {
    if (!EXISTING_PIN_PATTERN.test(pin)) throw new AppError('VALIDATION_ERROR', 'Enter your current payment PIN');
  }

  private hashVerificationCode(challengeId: string, userId: string, code: string, secret: string) {
    return createHmac('sha256', secret).update(`${challengeId}:${userId}:${code}`).digest('hex');
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
