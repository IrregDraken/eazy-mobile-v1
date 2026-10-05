import pg from 'pg';
import type { AppConfig } from '../config/env.js';
import { AppError } from '../middleware/errors.js';

const { Pool } = pg;
export type DbClient = pg.PoolClient;

export function createDbPool(config: AppConfig) {
  if (!config.DATABASE_URL) throw new AppError('SERVICE_UNAVAILABLE', 'Database is not configured');
  return new Pool({
    connectionString: config.DATABASE_URL,
    max: config.DB_POOL_MAX,
    idleTimeoutMillis: config.DB_IDLE_TIMEOUT_MS,
    connectionTimeoutMillis: config.DB_CONNECTION_TIMEOUT_MS,
    ssl: config.NODE_ENV === 'production' ? { rejectUnauthorized: false } : undefined
  });
}

export async function withTransaction<T>(pool: pg.Pool, work: (client: DbClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try { await client.query('ROLLBACK'); } catch { /* preserve original failure */ }
    throw error;
  } finally {
    client.release();
  }
}

export async function closeDbPool(pool: pg.Pool): Promise<void> {
  await pool.end();
}
