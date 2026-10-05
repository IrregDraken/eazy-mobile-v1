import { createHash, randomInt, randomUUID } from 'node:crypto';
import type { Pool } from 'pg';
import { AppError } from '../../middleware/errors.js';
import type { EmailProvider } from '../../providers/resend-email.js';
import type { AppConfig } from '../../config/env.js';

export interface EmailVerificationStart {
  challengeId: string;
  expiresInSeconds: number;
}

export interface EmailVerificationResult {
  challengeId: string;
  email: string;
  verified: true;
}

export class EmailVerificationService {
  constructor(private readonly pool: Pool, private readonly provider: EmailProvider, private readonly config: AppConfig) {}

  async requestCode(emailInput: string): Promise<EmailVerificationStart> {
    const email = normalizeEmail(emailInput);
    const ttlMinutes = this.config.OTP_TTL_MINUTES ?? 10;
    const maxAttempts = this.config.OTP_MAX_ATTEMPTS ?? 5;
    const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
    const challengeId = randomUUID();
    const expiresAt = new Date(Date.now() + ttlMinutes * 60_000);
    const digest = hashCode(challengeId, code);
    await this.pool.query(
      `INSERT INTO email_verification_challenges
         (id, email, code_digest, expires_at, max_attempts)
       VALUES ($1, $2, $3, $4, $5)`,
      [challengeId, email, digest, expiresAt, maxAttempts]
    );
    try {
      await this.provider.send({
        to: email,
        subject: 'Your Eazy verification code',
        text: `Your Eazy verification code is ${code}. It expires in ${ttlMinutes} minutes.`,
        html: `<p>Your Eazy verification code is <strong>${code}</strong>.</p><p>This code expires in ${ttlMinutes} minutes.</p>`
      });
    } catch (error) {
      await this.pool.query('DELETE FROM email_verification_challenges WHERE id = $1', [challengeId]);
      throw error;
    }
    return { challengeId, expiresInSeconds: ttlMinutes * 60 };
  }

  async verifyCode(challengeId: string, codeInput: string): Promise<EmailVerificationResult> {
    const code = codeInput.trim();
    if (!/^\d{6}$/.test(code)) throw new AppError('VALIDATION_ERROR', 'Verification code must be 6 digits');
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await client.query<{
        id: string; email: string; code_digest: string; expires_at: Date | string;
        attempts: number; max_attempts: number; verified_at: Date | string | null;
      }>(
        `SELECT id, email, code_digest, expires_at, attempts, max_attempts, verified_at
         FROM email_verification_challenges WHERE id = $1 FOR UPDATE`, [challengeId]
      );
      const challenge = result.rows[0];
      if (!challenge) throw new AppError('NOT_FOUND', 'Verification request not found');
      if (challenge.verified_at) throw new AppError('CONFLICT', 'Verification code has already been used');
      if (new Date(challenge.expires_at).getTime() <= Date.now()) throw new AppError('VALIDATION_ERROR', 'Verification code has expired');
      if (challenge.attempts >= challenge.max_attempts) throw new AppError('RATE_LIMITED', 'Too many verification attempts. Request a new code.');
      const valid = hashCode(challenge.id, code) === challenge.code_digest;
      if (!valid) {
        await client.query('UPDATE email_verification_challenges SET attempts = attempts + 1 WHERE id = $1', [challenge.id]);
        await client.query('COMMIT');
        throw new AppError('UNAUTHORIZED', 'Incorrect verification code');
      }
      await client.query('UPDATE email_verification_challenges SET verified_at = now() WHERE id = $1', [challenge.id]);
      await client.query('COMMIT');
      return { challengeId: challenge.id, email: challenge.email, verified: true };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }
}

function normalizeEmail(value: string): string {
  const email = value.trim().toLowerCase();
  if (!/^\S+@\S+\.\S+$/.test(email)) throw new AppError('VALIDATION_ERROR', 'Enter a valid email address');
  return email;
}

function hashCode(challengeId: string, code: string): string {
  return createHash('sha256').update(`${challengeId}:${code}`).digest('hex');
}
