import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../src/config/env.js';

const base = {
  NODE_ENV: 'production',
  PORT: '3000',
  LOG_LEVEL: 'info',
  DATABASE_URL: 'https://db.example.test/postgres',
  SUPABASE_URL: 'https://gwumpqikcujjgipvwtuu.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'test-service-role-key',
  FIREBASE_PROJECT_ID: 'eazy-test',
  FIREBASE_CLIENT_EMAIL: 'firebase@example.test',
  FIREBASE_PRIVATE_KEY: '-----BEGIN PRIVATE KEY-----\\nTEST\\n-----END PRIVATE KEY-----',
  CORS_ORIGIN: 'https://app.example.test',
  TRUST_PROXY: 'true',
  ENFORCE_HTTPS: 'true'
};

test('production config requires explicit CORS', () => {
  assert.throws(() => loadConfig({ ...base, CORS_ORIGIN: '*' }));
});

test('production config requires HTTPS enforcement and proxy trust', () => {
  assert.throws(() => loadConfig({ ...base, ENFORCE_HTTPS: 'false' }));
  assert.throws(() => loadConfig({ ...base, TRUST_PROXY: 'false' }));
});

test('production config accepts explicit deployment invariants', () => {
  const config = loadConfig(base);
  assert.equal(config.NODE_ENV, 'production');
  assert.equal(config.ENFORCE_HTTPS, true);
  assert.equal(config.TRUST_PROXY, true);
});
