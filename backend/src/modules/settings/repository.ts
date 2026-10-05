import type { Pool } from 'pg';
import { projectUserSettings, type UserSettings, type UserSettingsRow } from './types.js';
import type { SettingsPatch } from './schemas.js';
import { withTransaction } from '../../database/client.js';

const columns = 'language_code, theme, notify_follows, notify_likes, notify_comments';

export class SettingsRepository {
  constructor(private readonly pool: Pool) {}

  async get(userId: string): Promise<UserSettings> {
    await this.pool.query('INSERT INTO user_settings (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING', [userId]);
    const selected = await this.pool.query<UserSettingsRow>(
      `SELECT ${columns} FROM user_settings WHERE user_id = $1 LIMIT 1`, [userId]
    );
    const row = selected.rows[0];
    if (!row) throw new Error('SETTINGS_ROW_NOT_FOUND');
    return projectUserSettings(row);
  }

  async update(userId: string, patch: SettingsPatch): Promise<UserSettings> {
    const changed: string[] = [];
    return withTransaction(this.pool, async client => {
      await client.query('INSERT INTO user_settings (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING', [userId]);
      const selected = await client.query<UserSettingsRow>(
        `SELECT ${columns} FROM user_settings WHERE user_id = $1 LIMIT 1 FOR UPDATE`, [userId]
      );
      const current = selected.rows[0];
      if (!current) throw new Error('SETTINGS_ROW_NOT_FOUND');
      const next = projectUserSettings(current);
      if (patch.languageCode !== undefined) { next.languageCode = patch.languageCode; changed.push('language_code'); }
      if (patch.theme !== undefined) { next.theme = patch.theme; changed.push('theme'); }
      if (patch.notifications?.follows !== undefined) { next.notifications.follows = patch.notifications.follows; changed.push('notify_follows'); }
      if (patch.notifications?.likes !== undefined) { next.notifications.likes = patch.notifications.likes; changed.push('notify_likes'); }
      if (patch.notifications?.comments !== undefined) { next.notifications.comments = patch.notifications.comments; changed.push('notify_comments'); }
      const result = await client.query<UserSettingsRow>(
        `UPDATE user_settings
         SET language_code = $2, theme = $3, notify_follows = $4, notify_likes = $5, notify_comments = $6, updated_at = now()
         WHERE user_id = $1 RETURNING ${columns}`,
        [userId, next.languageCode, next.theme, next.notifications.follows, next.notifications.likes, next.notifications.comments]
      );
      const row = result.rows[0];
      if (!row) throw new Error('SETTINGS_ROW_NOT_FOUND');
      await client.query(
        `INSERT INTO security_events (user_id, event_type, severity, metadata)
         VALUES ($1, 'settings_updated', 'info', $2::jsonb)`,
        [userId, JSON.stringify({ changed })]
      );
      return projectUserSettings(row);
    });
  }
}
