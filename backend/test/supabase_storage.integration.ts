import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import pg from 'pg';
import { AccountDeletionService } from '../src/modules/auth/account-deletion.js';
import { SupabaseStorageProvider } from '../src/providers/supabase-storage.js';

const { Pool } = pg;

type IntegrationConfig = {
  projectRef: string;
  projectName: string;
  baseUrl: string;
  serviceRoleKey: string;
  bucket: string;
  databaseUrl: string;
};

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required for the Supabase integration harness`);
  return value;
}

function loadConfig(): IntegrationConfig {
  if (process.env.SUPABASE_TEST_NON_PRODUCTION !== 'true') {
    throw new Error('SUPABASE_TEST_NON_PRODUCTION=true is required; refusing to run against an unclassified project');
  }
  const projectRef = required('SUPABASE_TEST_PROJECT_REF');
  const projectName = required('SUPABASE_TEST_PROJECT_NAME');
  if (!/(test|staging|non[-_ ]?prod|sandbox)/i.test(projectName)) {
    throw new Error('SUPABASE_TEST_PROJECT_NAME must identify a non-production project');
  }
  const baseUrl = required('SUPABASE_TEST_URL').replace(/\/$/, '');
  const parsedUrl = new URL(baseUrl);
  if (parsedUrl.protocol !== 'https:' || parsedUrl.hostname !== `${projectRef}.supabase.co` || parsedUrl.pathname !== '/') {
    throw new Error('SUPABASE_TEST_URL must be the HTTPS URL for SUPABASE_TEST_PROJECT_REF');
  }
  const bucket = required('SUPABASE_TEST_BUCKET');
  const databaseUrl = required('SUPABASE_TEST_DATABASE_URL');
  const parsedDatabaseUrl = new URL(databaseUrl);
  if (!['postgres:', 'postgresql:'].includes(parsedDatabaseUrl.protocol) || !parsedDatabaseUrl.hostname.includes(projectRef)) {
    throw new Error('SUPABASE_TEST_DATABASE_URL must identify the same dedicated Supabase project');
  }
  return {
    projectRef,
    projectName,
    baseUrl,
    serviceRoleKey: required('SUPABASE_TEST_SERVICE_ROLE_KEY'),
    bucket,
    databaseUrl
  };
}

function providerFor(config: IntegrationConfig) {
  return new SupabaseStorageProvider({
    SUPABASE_URL: config.baseUrl,
    SUPABASE_SERVICE_ROLE_KEY: config.serviceRoleKey,
    MEDIA_BUCKET: config.bucket
  } as never);
}

function objectPath(config: IntegrationConfig, key: string): string {
  return `${config.baseUrl}/storage/v1/object/${encodeURIComponent(config.bucket)}/${key.split('/').map(encodeURIComponent).join('/')}`;
}

async function upload(config: IntegrationConfig, key: string, contents = 'synthetic-eazy-storage-test') {
  const response = await fetch(objectPath(config, key), {
    method: 'POST',
    headers: {
      authorization: `Bearer ${config.serviceRoleKey}`,
      apikey: config.serviceRoleKey,
      'content-type': 'text/plain',
      'x-upsert': 'true'
    },
    body: contents
  });
  if (!response.ok) throw new Error(`Synthetic upload failed with HTTP ${response.status}`);
  await response.arrayBuffer();
}

async function exists(config: IntegrationConfig, key: string): Promise<boolean> {
  const response = await fetch(objectPath(config, key), {
    headers: { authorization: `Bearer ${config.serviceRoleKey}`, apikey: config.serviceRoleKey }
  });
  await response.arrayBuffer();
  if (response.status === 404) return false;
  if (!response.ok) throw new Error(`Object verification failed with HTTP ${response.status}`);
  return true;
}

async function assertPrivateBucket(config: IntegrationConfig) {
  const response = await fetch(`${config.baseUrl}/storage/v1/bucket/${encodeURIComponent(config.bucket)}`, {
    headers: { authorization: `Bearer ${config.serviceRoleKey}`, apikey: config.serviceRoleKey }
  });
  const body = await response.json().catch(() => ({})) as { id?: string; public?: boolean };
  if (!response.ok) throw new Error(`Configured test bucket could not be inspected (HTTP ${response.status})`);
  if (body.id !== config.bucket || body.public !== false) {
    throw new Error('Configured Supabase test bucket must exist and be private');
  }
}

async function runStorageProviderChecks(config: IntegrationConfig, provider: SupabaseStorageProvider, runId: string) {
  const owned = Array.from({ length: 101 }, (_, index) => `${runId}/owned/${index}.txt`);
  const unrelated = `${runId}/unrelated/keep.txt`;
  for (const key of [...owned, unrelated]) await upload(config, key);

  const deleted = await provider.deleteObjects(owned);
  assert.deepEqual(deleted, { deleted: 101, requested: 101 });
  for (const key of owned) assert.equal(await exists(config, key), false, `owned object remains: ${key}`);
  assert.equal(await exists(config, unrelated), true, 'unrelated object was deleted');

  // A second exact delete verifies provider-level idempotency against already-absent objects.
  assert.deepEqual(await provider.deleteObjects(owned), { deleted: 101, requested: 101 });

  const retryKey = `${runId}/retry/transient.txt`;
  await upload(config, retryKey);
  const originalFetch = globalThis.fetch;
  let injectedTransientFailure = false;
  globalThis.fetch = async (input, init) => {
    const requestUrl = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url;
    if (!injectedTransientFailure && requestUrl.includes(`/storage/v1/object/remove/${encodeURIComponent(config.bucket)}`)) {
      injectedTransientFailure = true;
      return new Response(JSON.stringify({ message: 'synthetic transient integration failure' }), { status: 503 });
    }
    return originalFetch(input, init);
  };
  try {
    assert.deepEqual(await provider.deleteObjects([retryKey]), { deleted: 1, requested: 1 });
  } finally {
    globalThis.fetch = originalFetch;
  }
  assert.equal(injectedTransientFailure, true);
  assert.equal(await exists(config, retryKey), false, 'retry object remains after successful retry');
  await provider.deleteObjects([unrelated]);
  assert.equal(await exists(config, unrelated), false);
}

async function runDatabaseCleanupConsistencyCheck(config: IntegrationConfig, provider: SupabaseStorageProvider, runId: string) {
  const pool = new Pool({ connectionString: config.databaseUrl, ssl: { rejectUnauthorized: false } });
  const userId = randomUUID();
  const firebaseUid = `supabase-storage-test-${runId}`;
  const mediaKey = `${runId}/database/owned.txt`;
  const removed: string[] = [];
  try {
    await upload(config, mediaKey);
    await pool.query('INSERT INTO users (id, firebase_uid, email) VALUES ($1, $2, $3)', [userId, firebaseUid, `${firebaseUid}@example.test`]);
    const username = `test_${runId.replace(/[^a-z0-9]/gi, '').toLowerCase().slice(0, 26)}`;
    await pool.query('INSERT INTO profiles (user_id, username, display_name) VALUES ($1, $2, $3)', [userId, username, 'Storage test user']);
    const post = (await pool.query('INSERT INTO posts (author_id, content) VALUES ($1, $2) RETURNING id', [userId, 'synthetic storage test'])).rows[0].id;
    await pool.query('INSERT INTO post_media (post_id, storage_key, media_type) VALUES ($1, $2, $3)', [post, mediaKey, 'text/plain']);

    const service = new AccountDeletionService(pool, { deleteIdentity: async uid => { removed.push(uid); } }, undefined, provider);
    assert.deepEqual(await service.deleteAccount(userId, { ipAddress: '127.0.0.1' }), { deleted: true });
    assert.deepEqual(removed, [firebaseUid]);
    assert.equal(await exists(config, mediaKey), false, 'database-owned object remains after account deletion');

    const job = (await pool.query('SELECT status, identity_deleted FROM account_deletion_jobs WHERE user_id = $1', [userId])).rows[0];
    assert.deepEqual(job, { status: 'complete', identity_deleted: true });
    assert.deepEqual((await pool.query('SELECT status FROM account_deletion_media WHERE user_id = $1', [userId])).rows, [{ status: 'deleted' }]);

    assert.deepEqual(await service.deleteAccount(userId), { deleted: true });
    assert.deepEqual(removed, [firebaseUid], 'repeat deletion attempted identity removal twice');
  } finally {
    await pool.end();
  }
}

async function main() {
  const config = loadConfig();
  await assertPrivateBucket(config);
  const provider = providerFor(config);
  const runId = `run-${Date.now()}-${randomUUID().slice(0, 8)}`;
  await runStorageProviderChecks(config, provider, runId);
  await runDatabaseCleanupConsistencyCheck(config, provider, runId);
  console.log('Supabase Storage integration checks passed: private bucket, exact deletion, unrelated preservation, 101-object batching, retry, idempotency, and database cleanup state.');
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : 'Supabase Storage integration failed');
  process.exitCode = 1;
});
