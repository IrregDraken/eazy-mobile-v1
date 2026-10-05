import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { isIP } from 'node:net';
import type { Pool } from 'pg';
import { withTransaction, type DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { AuthContext } from '../../middleware/auth.js';
import type { FirebaseIdentity } from '../../providers/firebase-auth.js';
import type { AppConfig } from '../../config/env.js';

export interface AuthenticatedIdentity extends AuthContext {
  firebaseUid: string;
  sessionId: string;
}

export interface AuthUserRecord {
  user: { id: string; firebase_uid: string; email: string | null; phone: string | null; status: string };
  profile: { user_id: string; username: string; display_name: string } | null;
  session: { id: string; expires_at: string; created_at: string };
}

export interface SafeSession {
  id: string;
  createdAt: string;
  lastActivityAt: string | null;
  expiresAt: string;
  ipAddress: string | null;
  userAgent: string | null;
  current: boolean;
  status: 'active' | 'expired' | 'revoked';
}

export interface SessionTerminator {
  terminateSession(userId: string, sessionId: string): void;
  terminateUserSessions(userId: string): void;
}

export class AuthService {
  constructor(private readonly pool: Pool, private readonly config: AppConfig, private readonly terminator?: SessionTerminator) {}

  async provision(identity: FirebaseIdentity, metadata: { ipAddress?: string; userAgent?: string } = {}): Promise<{ context: AuthenticatedIdentity; record: AuthUserRecord }> {
    const firebaseUid = identity.firebaseUid;
    const authTime = finiteNumber(identity.claims.auth_time);
    if (!authTime) throw new AppError('UNAUTHORIZED', 'Invalid authentication');
    const providerSessionId = createHash('sha256').update(`${firebaseUid}:${authTime}`).digest('hex');
    return withTransaction(this.pool, async client => {
      const user = await this.findOrCreateUser(client, identity);
      if (user.status !== 'active') throw new AppError('FORBIDDEN', 'Account is not active');
      const profile = await this.ensureProfile(client, user.id, identity.firebaseUid, identity.claims);
      const session = await this.findOrCreateSession(client, user.id, providerSessionId, metadata);
      if (new Date(session.expires_at).getTime() <= Date.now()) throw new AppError('UNAUTHORIZED', 'Application session has expired');
      const live = await client.query<{ revoked_at: string | null; expires_at: string }>(
        `UPDATE sessions SET last_activity_at = now(), ip_address = COALESCE($3::inet, ip_address),
           user_agent = COALESCE($4, user_agent)
         WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL AND expires_at > now()
         RETURNING revoked_at, expires_at`,
        [session.id, user.id, validIp(metadata.ipAddress), boundedUserAgent(metadata.userAgent)]
      );
      if (!live.rowCount) throw new AppError('UNAUTHORIZED', 'Application session is no longer valid');
      return {
        context: { userId: user.id, firebaseUid: identity.firebaseUid, provider: 'firebase', claims: identity.claims, sessionId: session.id, account: { user, profile } },
        record: { user, profile, session: { id: session.id, expires_at: session.expires_at, created_at: session.created_at } }
      };
    });
  }

  async listSessions(userId: string, currentSessionId: string) {
    const result = await this.pool.query<{
      id: string; created_at: Date | string; last_activity_at: Date | string | null; expires_at: Date | string;
      ip_address: string | null; user_agent: string | null; revoked_at: Date | string | null;
    }>(
      `SELECT id, created_at, last_activity_at, expires_at, host(ip_address) AS ip_address, user_agent, revoked_at
       FROM sessions WHERE user_id = $1 ORDER BY created_at DESC, id DESC LIMIT 100`, [userId]
    );
    const now = Date.now();
    return { sessions: result.rows.map(row => ({
      id: row.id,
      createdAt: iso(row.created_at),
      lastActivityAt: row.last_activity_at ? iso(row.last_activity_at) : null,
      expiresAt: iso(row.expires_at),
      ipAddress: row.ip_address,
      userAgent: row.user_agent,
      current: row.id === currentSessionId,
      status: row.revoked_at ? 'revoked' as const : new Date(row.expires_at).getTime() <= now ? 'expired' as const : 'active' as const
    })) };
  }

  async revokeSession(userId: string, sessionId: string, metadata: { ipAddress?: string } = {}): Promise<void> {
    const revoked = await withTransaction(this.pool, async client => {
      const result = await client.query('UPDATE sessions SET revoked_at = now() WHERE id = $1 AND user_id = $2 AND revoked_at IS NULL RETURNING id', [sessionId, userId]);
      if (!result.rowCount) return false;
      await this.recordSecurityEvent(client, userId, 'session_revoked', metadata.ipAddress, { sessionId });
      return true;
    });
    if (!revoked) throw new AppError('NOT_FOUND', 'Session not found');
    this.terminator?.terminateSession(userId, sessionId);
  }

  async revokeAllSessions(userId: string, currentSessionId: string, metadata: { ipAddress?: string } = {}) {
    const result = await withTransaction(this.pool, async client => {
      const result = await client.query<{ id: string }>(
        `UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL RETURNING id`, [userId]
      );
      await this.recordSecurityEvent(client, userId, 'sessions_revoked_all', metadata.ipAddress, { count: result.rowCount ?? 0 });
      return { revoked: result.rowCount ?? 0, currentSessionRevoked: result.rows.some(row => row.id === currentSessionId) };
    });
    this.terminator?.terminateUserSessions(userId);
    return result;
  }

  private async recordSecurityEvent(client: DbClient, userId: string, eventType: string, ipAddress: string | undefined, metadata: Record<string, unknown>) {
    await client.query(
      `INSERT INTO security_events (user_id, event_type, severity, ip_address, metadata)
       VALUES ($1, $2, 'info', $3::inet, $4::jsonb)`,
      [userId, eventType, validIp(ipAddress), JSON.stringify(metadata)]
    );
  }

  private async findOrCreateUser(client: DbClient, identity: FirebaseIdentity) {
    const emailVerified = identity.claims.email_verified === true;
    const result = await client.query<{ id: string; firebase_uid: string; email: string | null; phone: string | null; status: string }>(
      `INSERT INTO users (firebase_uid, email, phone, email_verified_at, status)
       VALUES ($1, $2, $3, CASE WHEN $4::boolean THEN now() ELSE NULL END, 'active')
       ON CONFLICT (firebase_uid) DO UPDATE SET
         email = COALESCE(EXCLUDED.email, users.email),
         phone = COALESCE(EXCLUDED.phone, users.phone),
         email_verified_at = COALESCE(users.email_verified_at, EXCLUDED.email_verified_at),
         updated_at = now()
       RETURNING id, firebase_uid, email, phone, status`,
      [identity.firebaseUid, stringClaim(identity.claims, 'email'), stringClaim(identity.claims, 'phone_number'), emailVerified]
    );
    const user = result.rows[0];
    if (!user) throw new AppError('SERVICE_UNAVAILABLE', 'Unable to provision user');
    return user;
  }

  private async ensureProfile(client: DbClient, userId: string, firebaseUid: string, claims: Record<string, unknown>) {
    const existing = await client.query<{ user_id: string; username: string; display_name: string }>('SELECT user_id, username, display_name FROM profiles WHERE user_id = $1 LIMIT 1', [userId]);
    if (existing.rows[0]) return existing.rows[0] ?? null;
    const base = `user_${firebaseUid.toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 24) || randomUUID().replace(/-/g, '').slice(0, 24)}`;
    for (let attempt = 0; attempt < 5; attempt += 1) {
      const username = `${base.slice(0, 31 - String(attempt).length)}${attempt || ''}`;
      try {
        const created = await client.query<{ user_id: string; username: string; display_name: string }>(
          `INSERT INTO profiles (user_id, username, display_name) VALUES ($1, $2, $3) RETURNING user_id, username, display_name`,
          [userId, username, stringClaim(claims, 'name') ?? 'Eazy User']
        );
        return created.rows[0] ?? null;
      } catch (error: unknown) { if ((error as { code?: string }).code !== '23505') throw error; }
    }
    throw new AppError('CONFLICT', 'Unable to create a unique profile username');
  }

  private async findOrCreateSession(client: DbClient, userId: string, providerSessionId: string, metadata: { ipAddress?: string; userAgent?: string }) {
    const inserted = await client.query<{ id: string }>(
      `INSERT INTO sessions (user_id, provider_session_id, token_hash, expires_at, ip_address, user_agent)
       VALUES ($1, $2, $3, now() + ($4 * interval '1 day'), $5::inet, $6)
       ON CONFLICT (user_id, provider_session_id) WHERE provider_session_id IS NOT NULL DO NOTHING
       RETURNING id`,
      [userId, providerSessionId, createHash('sha256').update(randomBytes(32)).digest('hex'), this.config.EAZY_SESSION_TTL_DAYS, validIp(metadata.ipAddress), boundedUserAgent(metadata.userAgent)]
    );
    const found = await client.query<{ id: string; expires_at: string; created_at: string }>(
      `SELECT id, expires_at, created_at FROM sessions
       WHERE user_id = $1 AND provider_session_id = $2 LIMIT 1 FOR UPDATE`, [userId, providerSessionId]
    );
    const existing = found.rows[0];
    if (!existing) throw new AppError('SERVICE_UNAVAILABLE', 'Unable to create application session');
    if (inserted.rowCount) {
      await this.recordSecurityEvent(client, userId, 'session_created', metadata.ipAddress, { provider: 'firebase' });
    }
    return existing;
  }
}

function finiteNumber(value: unknown): number | null { return typeof value === 'number' && Number.isFinite(value) && value > 0 ? value : null; }
function stringClaim(claims: Record<string, unknown>, key: string): string | null { return typeof claims[key] === 'string' ? claims[key] : null; }
function boundedUserAgent(value?: string): string | null { return value ? value.slice(0, 512) : null; }
function validIp(value?: string): string | null { return value && isIP(value) ? value : null; }
function iso(value: Date | string): string { return value instanceof Date ? value.toISOString() : new Date(value).toISOString(); }
