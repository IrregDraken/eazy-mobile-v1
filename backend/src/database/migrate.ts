import { access, readdir, readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import { loadConfig } from '../config/env.js';
import { createLogger } from '../config/logger.js';

const { Pool } = pg;
const migrationDirectoryCandidates = [
  fileURLToPath(new URL('../../migrations', import.meta.url)),
  fileURLToPath(new URL('../../../migrations', import.meta.url)),
  join(process.cwd(), 'migrations'),
  join(process.cwd(), 'backend/migrations')
];
async function getMigrationsDirectory() {
  for (const candidate of migrationDirectoryCandidates) {
    try { await access(candidate); return candidate; } catch { /* try next candidate */ }
  }
  throw new Error('Migrations directory not found');
}
const hostedMigrationNames: Record<string, string> = {
  '001_initial_schema.sql': 'initial_eazy_v2_schema',
  '002_profile_onboarding.sql': 'profile_onboarding',
  '003_social_indexes.sql': 'social_indexes',
  '004_rls_policies.sql': 'rls_policies',
  '005_feed_indexes.sql': 'feed_indexes',
  '006_marketplace_discovery.sql': 'marketplace_discovery',
  '007_order_item_snapshots.sql': 'order_item_snapshots',
  '008_chat_direct_uniqueness.sql': 'chat_direct_uniqueness',
  '009_payment_order_link.sql': 'wallet_payments_order_link',
  '010_notifications_presentation.sql': 'notifications_presentation',
  '011_assist_indexes.sql': 'assist_indexes',
  '012_settings_security.sql': 'settings_security',
  '013_email_verification_challenges.sql': 'email_verification_challenges',
  '014_bank_transfers.sql': 'bank_transfers',
  '015_wallet_virtual_accounts.sql': 'wallet_virtual_accounts',
  '016_financial_rls.sql': 'financial_rls',
  '017_eazy_media_bucket.sql': 'eazy_media_bucket',
  '018_email_verification_users.sql': 'email_verification_users',
  '019_profile_middle_name.sql': 'profile_middle_name'
};

async function main() {
  const config = loadConfig();
  const logger = createLogger(config);
  if (!config.DATABASE_URL) {
    throw new Error('DATABASE_URL is required to run migrations');
  }

  const pool = new Pool({ connectionString: config.DATABASE_URL, ssl: config.NODE_ENV === 'production' ? { rejectUnauthorized: false } : undefined });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', ['eazy:migrations']);
    await client.query(`CREATE TABLE IF NOT EXISTS schema_migrations (
      version text PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )`);

    const migrationsDirectory = await getMigrationsDirectory();
    const files = (await readdir(migrationsDirectory)).filter(file => /^\d+_.+\.sql$/.test(file)).sort();
    const applied = new Set((await client.query<{ version: string }>('SELECT version FROM schema_migrations ORDER BY version')).rows.map(row => row.version));
    for (const file of files) {
      if (applied.has(file)) continue;
      const hostedName = hostedMigrationNames[file];
      if (hostedName) {
        const hostedTable = await client.query<{ exists: boolean }>(
          `SELECT EXISTS (
             SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'supabase_migrations' AND table_name = 'schema_migrations'
           ) AS exists`
        );
        if (hostedTable.rows[0]?.exists) {
          const hostedApplied = await client.query(
            'SELECT 1 FROM supabase_migrations.schema_migrations WHERE name = $1 LIMIT 1',
            [hostedName]
          );
          if (hostedApplied.rowCount) {
            await client.query('INSERT INTO schema_migrations (version) VALUES ($1) ON CONFLICT DO NOTHING', [file]);
            logger.info({ event: 'migration.recognized', migration: file, hostedMigration: hostedName }, 'recognized hosted migration');
            continue;
          }
        }
      }
      const sql = await readFile(join(migrationsDirectory, file), 'utf8');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [file]);
      logger.info({ event: 'migration.applied', migration: file }, 'applied migration');
    }
    await client.query('COMMIT');
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
    await pool.end();
  }
}

main().catch(error => {
  const config = loadConfig();
  const logger = createLogger(config);
  logger.error({ event: 'migration.failed', error: error instanceof Error ? { name: error.name, message: error.message } : { name: 'UnknownError', message: 'Unknown error' } }, 'migration failed');
  process.exitCode = 1;
});
