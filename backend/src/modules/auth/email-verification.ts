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

  async requestCode(emailInput: string, allowedFirebaseUid?: string): Promise<EmailVerificationStart> {
    const email = normalizeEmail(emailInput);
    const existing = await this.pool.query<{ id: string }>(
      `SELECT id FROM users
       WHERE lower(email) = $1 AND status <> 'deleted'
         AND ($2::text IS NULL OR COALESCE(firebase_uid, '') <> $2)
       LIMIT 1`,
      [email, allowedFirebaseUid ?? null]
    );
    if (existing.rowCount) {
      throw new AppError('CONFLICT', 'An account with this email already exists. Sign in instead.');
    }

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
        text: [
          'Welcome to Eazy',
          '',
          'Use the verification code below to finish setting up your account:',
          '',
          code,
          '',
          `This code expires in ${ttlMinutes} minutes.`,
          '',
          'For your security, never share this code with anyone, including someone claiming to be from Eazy.',
          'If you did not request this code, you can safely ignore this email.',
          '',
          'Eazy | Your world, made easier.'
        ].join('\n'),
        html: verificationEmailHtml(code, ttlMinutes)
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
      if (new Date(challenge.expires_at).getTime() <= Date.now()) throw new AppError('VALIDATION_ERROR', 'Verification code has expired');
      if (challenge.attempts >= challenge.max_attempts) {
        throw new AppError('RATE_LIMITED', 'Too many verification attempts. Request a new code.');
      }
      const valid = hashCode(challenge.id, code) === challenge.code_digest;
      if (!valid) {
        await client.query('UPDATE email_verification_challenges SET attempts = attempts + 1 WHERE id = $1', [challenge.id]);
        await client.query('COMMIT');
        throw new AppError('UNAUTHORIZED', 'Incorrect verification code');
      }
      // The client first verifies the code before creating its Firebase identity.
      // It then repeats this request with authentication so this verified challenge
      // can be bound to that identity and Firebase can be marked emailVerified.
      if (!challenge.verified_at) {
        await client.query('UPDATE email_verification_challenges SET verified_at = now() WHERE id = $1', [challenge.id]);
      }
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

function verificationEmailHtml(code: string, ttlMinutes: number): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"></head><body style="margin:0;padding:0;background:#f1f5f1;font-family:Arial,Helvetica,sans-serif;color:#14241b"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f1f5f1;padding:28px 12px"><tr><td align="center"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#ffffff;border:1px solid #dce6dc;border-radius:20px;overflow:hidden"><tr><td style="background:#061b11;padding:30px 32px 28px"><div style="font-size:13px;font-weight:800;letter-spacing:4px;color:#b8f34a">EAZY</div><h1 style="margin:22px 0 8px;color:#ffffff;font-size:27px;line-height:1.25;font-weight:700">Your world, made easier.</h1><p style="margin:0;color:#c4d4c9;font-size:15px;line-height:1.6">One quick step to verify your email.</p></td></tr><tr><td style="padding:30px 32px"><p style="margin:0 0 12px;font-size:16px;line-height:1.7">Use this verification code to continue creating your Eazy account.</p><div style="margin:24px 0;padding:24px 12px;text-align:center;background:#f2f8ec;border:1px solid #d8e9c8;border-radius:14px"><div style="font-size:11px;letter-spacing:2px;font-weight:700;color:#59724e;text-transform:uppercase;margin-bottom:12px">Your verification code</div><div style="font-family:Arial,Helvetica,sans-serif;font-size:36px;line-height:1.2;font-weight:800;letter-spacing:8px;color:#102b1b">${code}</div></div><p style="margin:0;color:#536459;font-size:14px;line-height:1.7">This code expires in <strong style="color:#172c20">${ttlMinutes} minutes</strong>. If it expires, request a new one in the app.</p><div style="margin-top:26px;padding:16px 18px;border-radius:12px;background:#f7f8f6"><p style="margin:0 0 6px;font-size:13px;font-weight:700;color:#263c2d">Keep your account safe</p><p style="margin:0;font-size:13px;line-height:1.7;color:#5a695e">Never share this code with anyone, including someone claiming to be from Eazy. If you did not request it, you can safely ignore this email.</p></div></td></tr><tr><td style="padding:20px 32px;background:#f8faf7;border-top:1px solid #e5ebe4"><p style="margin:0;font-size:12px;line-height:1.7;color:#6a786e">This is an automated security email from Eazy. Replies may not be monitored.<br>© Eazy. Your world, made easier.</p></td></tr></table></td></tr></table></body></html>`;
}
