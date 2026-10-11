import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../src/config/env.js';
import { AuthService } from '../src/modules/auth/service.js';
import { AppError } from '../src/middleware/errors.js';

const config = loadConfig({ NODE_ENV: 'test', PORT: '3000', LOG_LEVEL: 'silent', EAZY_SESSION_TTL_DAYS: '30' });

test('Firebase provisioning cannot refresh identifiers or reactivate a deleted tombstone', async () => {
  const sql: string[] = [];
  const query = async (statement: string) => {
    sql.push(statement);
    if (/^(BEGIN|COMMIT|ROLLBACK)$/.test(statement)) return { rows: [], rowCount: 0 };
    if (statement.includes('INSERT INTO users')) return { rows: [], rowCount: 0 };
    if (statement.includes('SELECT status FROM users WHERE firebase_uid')) return { rows: [{ status: 'deleted' }], rowCount: 1 };
    throw new Error(`Unexpected SQL: ${statement}`);
  };
  const client = { query, release: () => undefined };
  const pool = { connect: async () => client, query } as never;
  const service = new AuthService(pool, config);
  await assert.rejects(
    () => service.provision({ firebaseUid: 'deleted-firebase-user', claims: { auth_time: 1_760_000_000, email: 'new@example.test', phone_number: '+2348000000000' } }),
    (error: unknown) => error instanceof AppError && error.code === 'FORBIDDEN'
  );
  const userUpsert = sql.find(statement => statement.includes('INSERT INTO users'));
  assert.ok(userUpsert?.includes('WHERE users.status = \'active\''));
  assert.equal(sql.some(statement => statement.includes('UPDATE users SET email')), false);
});
