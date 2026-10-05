import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import type { AssistMessageRow, AssistSessionRow } from './types.js';

export interface AssistRepositoryContract {
  createSession(userId: string): Promise<AssistSessionRow>;
  listSessions(userId: string, page: number, limit: number): Promise<{ items: AssistSessionRow[]; total: number }>;
  getSession(userId: string, sessionId: string): Promise<AssistSessionRow | null>;
  closeSession(userId: string, sessionId: string): Promise<AssistSessionRow | null>;
  insertMessage(client: DbClient, userId: string, sessionId: string, role: 'user' | 'assistant', content: string): Promise<AssistMessageRow | null>;
  listMessages(userId: string, sessionId: string, page: number, limit: number): Promise<{ items: AssistMessageRow[]; total: number }>;
  recentMessages(userId: string, sessionId: string, limit: number): Promise<AssistMessageRow[]>;
}

export class AssistRepository implements AssistRepositoryContract {
  constructor(private readonly pool: Pool) {}

  async createSession(userId: string): Promise<AssistSessionRow> {
    const result = await this.pool.query<AssistSessionRow>(
      `INSERT INTO assist_sessions (user_id) VALUES ($1)
       RETURNING id, status, created_at, updated_at`,
      [userId]
    );
    const session = result.rows[0];
    if (!session) throw new Error('Assist session insert did not return a row');
    return session;
  }

  async listSessions(userId: string, page: number, limit: number): Promise<{ items: AssistSessionRow[]; total: number }> {
    const [count, result] = await Promise.all([
      this.pool.query<{ count: string }>('SELECT count(*)::text AS count FROM assist_sessions WHERE user_id = $1 LIMIT 1', [userId]),
      this.pool.query<AssistSessionRow>(
        `SELECT id, status, created_at, updated_at FROM assist_sessions
         WHERE user_id = $1 ORDER BY updated_at DESC, id DESC LIMIT $2 OFFSET $3`,
        [userId, limit, (page - 1) * limit]
      )
    ]);
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async getSession(userId: string, sessionId: string): Promise<AssistSessionRow | null> {
    const result = await this.pool.query<AssistSessionRow>(
      `SELECT id, status, created_at, updated_at FROM assist_sessions
       WHERE user_id = $1 AND id = $2 LIMIT 1`,
      [userId, sessionId]
    );
    return result.rows[0] ?? null;
  }

  async closeSession(userId: string, sessionId: string): Promise<AssistSessionRow | null> {
    const result = await this.pool.query<AssistSessionRow>(
      `UPDATE assist_sessions SET status = 'closed', updated_at = now()
       WHERE user_id = $1 AND id = $2 AND status = 'active'
       RETURNING id, status, created_at, updated_at`,
      [userId, sessionId]
    );
    return result.rows[0] ?? this.getSession(userId, sessionId);
  }

  async insertMessage(client: DbClient, userId: string, sessionId: string, role: 'user' | 'assistant', content: string): Promise<AssistMessageRow | null> {
    const result = await client.query<AssistMessageRow>(
      `WITH owned_session AS (
         UPDATE assist_sessions SET updated_at = now()
         WHERE id = $1 AND user_id = $2 AND status = 'active'
         RETURNING id
       )
       INSERT INTO assist_messages (session_id, role, content)
       SELECT id, $3, $4 FROM owned_session
       RETURNING id, session_id, role, content, provider_reference, created_at`,
      [sessionId, userId, role, content]
    );
    return result.rows[0] ?? null;
  }

  async listMessages(userId: string, sessionId: string, page: number, limit: number): Promise<{ items: AssistMessageRow[]; total: number }> {
    const [count, result] = await Promise.all([
      this.pool.query<{ count: string }>(
        `SELECT count(*)::text AS count FROM assist_messages m
         JOIN assist_sessions s ON s.id = m.session_id
         WHERE s.user_id = $1 AND s.id = $2 AND m.role IN ('user', 'assistant') LIMIT 1`,
        [userId, sessionId]
      ),
      this.pool.query<AssistMessageRow>(
        `SELECT m.id, m.session_id, m.role, m.content, m.provider_reference, m.created_at
         FROM assist_messages m JOIN assist_sessions s ON s.id = m.session_id
         WHERE s.user_id = $1 AND s.id = $2 AND m.role IN ('user', 'assistant')
         ORDER BY m.created_at DESC, m.id DESC LIMIT $3 OFFSET $4`,
        [userId, sessionId, limit, (page - 1) * limit]
      )
    ]);
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async recentMessages(userId: string, sessionId: string, limit: number): Promise<AssistMessageRow[]> {
    const result = await this.pool.query<AssistMessageRow>(
      `SELECT m.id, m.session_id, m.role, m.content, m.provider_reference, m.created_at
       FROM assist_messages m JOIN assist_sessions s ON s.id = m.session_id
       WHERE s.user_id = $1 AND s.id = $2 AND s.status = 'active' AND m.role IN ('user', 'assistant')
       ORDER BY m.created_at DESC, m.id DESC LIMIT $3`,
      [userId, sessionId, limit]
    );
    return result.rows;
  }
}
