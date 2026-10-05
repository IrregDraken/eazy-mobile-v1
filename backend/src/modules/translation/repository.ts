import type { Pool } from 'pg';
import type { TranslationRecord, TranslationRepositoryContract, TranslationRequestRow } from './types.js';
import { normalizeTranslationRecord } from './types.js';

export class TranslationRepository implements TranslationRepositoryContract {
  constructor(private readonly pool: Pool) {}

  async createPending(userId: string, input: { text: string; sourceLanguage: string; targetLanguage: string }) {
    const result = await this.pool.query<{ id: string; created_at: Date | string }>(
      `INSERT INTO translation_requests (user_id, source_language, target_language, original_content, status)
       VALUES ($1, $2, $3, $4, 'pending')
       RETURNING id, created_at`,
      [userId, input.sourceLanguage, input.targetLanguage, input.text]
    );
    const row = result.rows[0];
    if (!row) throw new Error('Translation request was not persisted');
    return { id: row.id, createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at };
  }

  async markSucceeded(userId: string, requestId: string, translatedText: string, providerReference: string | null): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE translation_requests
       SET translated_content = $3, provider_reference = $4, status = 'succeeded', updated_at = now()
       WHERE id = $1 AND user_id = $2 AND status = 'pending'
       RETURNING id`,
      [requestId, userId, translatedText, providerReference]
    );
    return result.rowCount === 1;
  }

  async markFailed(userId: string, requestId: string): Promise<boolean> {
    const result = await this.pool.query(
      `UPDATE translation_requests
       SET status = 'failed', translated_content = NULL, provider_reference = NULL, updated_at = now()
       WHERE id = $1 AND user_id = $2 AND status = 'pending'
       RETURNING id`,
      [requestId, userId]
    );
    return result.rowCount === 1;
  }

  async getForUser(userId: string, requestId: string): Promise<TranslationRecord | null> {
    const result = await this.pool.query<TranslationRequestRow>(
      `SELECT id, source_language, target_language, original_content, translated_content, status, created_at
       FROM translation_requests WHERE id = $1 AND user_id = $2 LIMIT 1`,
      [requestId, userId]
    );
    return result.rows[0] ? normalizeTranslationRecord(result.rows[0]) : null;
  }
}
