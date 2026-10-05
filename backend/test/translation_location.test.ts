import assert from 'node:assert/strict';
import test from 'node:test';
import type { RequestHandler } from 'express';
import { createApp } from '../src/app.js';
import { createLogger } from '../src/config/logger.js';
import { AppError } from '../src/middleware/errors.js';
import { LocationRepository } from '../src/modules/location/repository.js';
import { createLocationRouter } from '../src/modules/location/routes.js';
import { locationSearchSchema, reverseGeocodeSchema } from '../src/modules/location/schemas.js';
import { LocationService } from '../src/modules/location/service.js';
import type { LocationProvider } from '../src/modules/location/types.js';
import { UnavailableLocationProvider } from '../src/modules/location/providers/unavailable.js';
import { translationRequestIdSchema, translateSchema } from '../src/modules/translation/schemas.js';
import { createTranslationRouter } from '../src/modules/translation/routes.js';
import { TranslationService } from '../src/modules/translation/service.js';
import { TranslationRepository } from '../src/modules/translation/repository.js';
import type { TranslationInput, TranslationProvider, TranslationRecord, TranslationRepositoryContract } from '../src/modules/translation/types.js';
import { UnavailableTranslationProvider } from '../src/modules/translation/providers/unavailable.js';

const userA = '00000000-0000-4000-8000-000000000001';
const userB = '00000000-0000-4000-8000-000000000002';
const requestId = '10000000-0000-4000-8000-000000000001';
const config = { NODE_ENV: 'test', PORT: 3000, LOG_LEVEL: 'silent', DATABASE_URL: undefined, CORS_ORIGIN: '*', SUPABASE_PROJECT_REF: undefined, SUPABASE_URL: undefined, SUPABASE_DB_HOST: undefined, TRUST_PROXY: false, ENFORCE_HTTPS: false, DB_POOL_MAX: 10, DB_IDLE_TIMEOUT_MS: 30000, DB_CONNECTION_TIMEOUT_MS: 5000, RATE_LIMIT_WINDOW_MS: 60000, RATE_LIMIT_MAX: 100, FIREBASE_PROJECT_ID: undefined, FIREBASE_CLIENT_EMAIL: undefined, FIREBASE_PRIVATE_KEY: undefined, FIREBASE_CHECK_REVOKED: true, EAZY_SESSION_TTL_DAYS: 30 } as const;

function translationRepository() {
  const records = new Map<string, TranslationRecord & { userId: string; providerReference: string | null }>();
  let idCounter = 0;
  const repository: TranslationRepositoryContract = {
    createPending: async (userId, input) => {
      idCounter++;
      const id = idCounter === 1 ? requestId : `10000000-0000-4000-8000-${String(idCounter).padStart(12, '0')}`;
      const createdAt = '2026-09-24T12:00:00.000Z';
      records.set(id, { id, userId, sourceLanguage: input.sourceLanguage, targetLanguage: input.targetLanguage, originalContent: input.text, translatedContent: null, status: 'pending', createdAt, providerReference: null });
      return { id, createdAt };
    },
    markSucceeded: async (userId, id, translatedText, providerReference) => {
      const record = records.get(id);
      if (!record || record.userId !== userId || record.status !== 'pending') return false;
      record.translatedContent = translatedText;
      record.providerReference = providerReference;
      record.status = 'succeeded';
      return true;
    },
    markFailed: async (userId, id) => {
      const record = records.get(id);
      if (!record || record.userId !== userId || record.status !== 'pending') return false;
      record.status = 'failed';
      record.translatedContent = null;
      record.providerReference = null;
      return true;
    },
    getForUser: async (userId, id) => {
      const record = records.get(id);
      if (!record || record.userId !== userId) return null;
      const { providerReference: _providerReference, userId: _userId, ...publicRecord } = record;
      return publicRecord;
    }
  };
  return { records, repository };
}

function appWithAuth(translationRouter: ReturnType<typeof createTranslationRouter>, locationRouter: ReturnType<typeof createLocationRouter>) {
  const auth: RequestHandler = (request, _response, next) => {
    if (request.header('authorization') === 'Bearer test-token') request.auth = { userId: userA, provider: 'test', claims: {} };
    next();
  };
  return createApp(config, createLogger(config), { authMiddleware: auth, translationRouter, locationRouter });
}

async function withServer(app: ReturnType<typeof appWithAuth>, run: (baseUrl: string) => Promise<void>) {
  const server = app.listen(0);
  try {
    const address = server.address();
    assert.ok(address && typeof address !== 'string');
    await run(`http://127.0.0.1:${address.port}`);
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
}

test('translation input canonicalizes BCP 47 language tags and rejects invalid or incompatible inputs', () => {
  assert.deepEqual(translateSchema.parse({ text: '  Hello  ', targetLanguage: 'FR', sourceLanguage: 'en-us' }), { text: 'Hello', targetLanguage: 'fr', sourceLanguage: 'en-US' });
  assert.throws(() => translateSchema.parse({ text: '   ', targetLanguage: 'fr' }));
  assert.throws(() => translateSchema.parse({ text: 'x'.repeat(5001), targetLanguage: 'fr' }));
  assert.throws(() => translateSchema.parse({ text: 'Hello', targetLanguage: 'not_a_language' }));
  assert.throws(() => translateSchema.parse({ text: 'Hello', targetLanguage: 'en', sourceLanguage: 'EN' }));
  assert.throws(() => translateSchema.parse({ text: 'Hello', targetLanguage: 'fr', provider: 'vendor' }));
  assert.throws(() => translationRequestIdSchema.parse({ requestId, user_id: userB }));
});

test('translation service calls the injected provider, persists the result, and returns no provider reference', async () => {
  const { repository, records } = translationRepository();
  let providerInput: TranslationInput | null = null;
  const provider: TranslationProvider = {
    getCapabilities: () => ({ available: true, supportedLanguages: ['en', 'fr'] }),
    translate: async input => { providerInput = { text: input.text, targetLanguage: input.target, ...(input.source ? { sourceLanguage: input.source } : {}) }; return { text: 'Bonjour', providerReference: 'provider-secret-internal-id' }; }
  };
  const service = new TranslationService(provider, repository);
  const result = await service.translate(userA, { text: 'Hello', sourceLanguage: 'en', targetLanguage: 'fr' });
  assert.deepEqual(providerInput, { text: 'Hello', sourceLanguage: 'en', targetLanguage: 'fr' });
  assert.equal(result.translatedText, 'Bonjour');
  assert.equal(result.status, 'succeeded');
  assert.equal(JSON.stringify(result).includes('provider-secret'), false);
  assert.equal(records.get(result.id)?.providerReference, 'provider-secret-internal-id');
  assert.deepEqual(service.capabilities(), { providerAvailable: true, supportedLanguages: ['en', 'fr'] });
});

test('translation persists source mode as auto without claiming language detection', async () => {
  const { repository, records } = translationRepository();
  const provider: TranslationProvider = { getCapabilities: () => ({ available: true, supportedLanguages: null }), translate: async () => ({ text: 'Salut' }) };
  const result = await new TranslationService(provider, repository).translate(userA, { text: 'Hi', targetLanguage: 'fr' });
  assert.equal(result.sourceLanguage, 'auto');
  assert.equal(records.get(result.id)?.sourceLanguage, 'auto');
});

test('translation rejects provider-unsupported languages without calling it and marks the request failed', async () => {
  const { repository, records } = translationRepository();
  let called = false;
  const provider: TranslationProvider = { getCapabilities: () => ({ available: true, supportedLanguages: ['en'] }), translate: async () => { called = true; return { text: 'unexpected' }; } };
  await assert.rejects(() => new TranslationService(provider, repository).translate(userA, { text: 'Hello', targetLanguage: 'fr' }), (error: unknown) => error instanceof AppError && error.code === 'VALIDATION_ERROR');
  assert.equal(called, false);
  assert.equal([...records.values()][0]?.status, 'failed');
});

test('unavailable translation provider returns 503 and stores a failed request without translated content', async () => {
  const { repository, records } = translationRepository();
  const service = new TranslationService(new UnavailableTranslationProvider(), repository);
  assert.deepEqual(service.capabilities(), { providerAvailable: false, supportedLanguages: null });
  await assert.rejects(() => service.translate(userA, { text: 'Hello', targetLanguage: 'fr' }), (error: unknown) => error instanceof AppError && error.code === 'SERVICE_UNAVAILABLE' && error.statusCode === 503);
  assert.equal([...records.values()][0]?.status, 'failed');
  assert.equal([...records.values()][0]?.translatedContent, null);
});

test('translation history is owner-scoped and omits internal provider metadata', async () => {
  const { repository } = translationRepository();
  const provider: TranslationProvider = { getCapabilities: () => ({ available: true, supportedLanguages: null }), translate: async () => ({ text: 'Salut', providerReference: 'private-ref' }) };
  const service = new TranslationService(provider, repository);
  const result = await service.translate(userA, { text: 'Hi', targetLanguage: 'fr' });
  assert.equal((await service.getRequest(userA, result.id)).request.translatedContent, 'Salut');
  await assert.rejects(() => service.getRequest(userB, result.id), (error: unknown) => error instanceof AppError && error.code === 'NOT_FOUND');
  assert.equal(JSON.stringify(await service.getRequest(userA, result.id)).includes('private-ref'), false);
});

test('translation provider exceptions persist failure and return a generic 503', async () => {
  const { repository, records } = translationRepository();
  const provider: TranslationProvider = { getCapabilities: () => ({ available: true, supportedLanguages: null }), translate: async () => { throw new Error('secret token=do-not-leak'); } };
  const error = await new TranslationService(provider, repository).translate(userA, { text: 'Hello', targetLanguage: 'fr' }).then(() => null, caught => caught);
  assert.ok(error instanceof AppError);
  assert.equal(error.code, 'SERVICE_UNAVAILABLE');
  assert.equal(error.statusCode, 503);
  assert.equal(error.message.includes('do-not-leak'), false);
  assert.equal([...records.values()][0]?.status, 'failed');
});

test('translation SQL persists to existing fields and scopes every result update/read by authenticated owner', async () => {
  const statements: { sql: string; params: unknown[] }[] = [];
  const pool = {
    query: async (sql: string, params: unknown[]) => {
      statements.push({ sql, params });
      if (sql.includes('INSERT INTO translation_requests')) return { rows: [{ id: requestId, created_at: '2026-09-24T12:00:00.000Z' }], rowCount: 1 };
      if (sql.includes('UPDATE translation_requests')) return { rows: [{ id: requestId }], rowCount: 1 };
      return { rows: [{ id: requestId, source_language: 'auto', target_language: 'fr', original_content: 'Hello', translated_content: 'Salut', status: 'succeeded', created_at: '2026-09-24T12:00:00.000Z' }], rowCount: 1 };
    }
  };
  const repository = new TranslationRepository(pool as never);
  assert.deepEqual(await repository.createPending(userA, { text: 'Hello', sourceLanguage: 'auto', targetLanguage: 'fr' }), { id: requestId, createdAt: '2026-09-24T12:00:00.000Z' });
  assert.equal(await repository.markSucceeded(userA, requestId, 'Salut', 'private-reference'), true);
  const stored = await repository.getForUser(userA, requestId);
  assert.equal(stored?.status, 'succeeded');
  assert.equal(stored?.translatedContent, 'Salut');
  assert.equal(statements[0]?.sql.includes('source_language, target_language, original_content, status'), true);
  assert.equal(statements[1]?.sql.includes('WHERE id = $1 AND user_id = $2 AND status = \'pending\''), true);
  assert.equal(statements[2]?.sql.includes('WHERE id = $1 AND user_id = $2 LIMIT 1'), true);
  assert.equal(statements.some(statement => statement.sql.includes('provider_reference') && statement.sql.includes('SELECT')), false);
  assert.ok(statements.every(statement => statement.params.includes(userA)));
});

test('location schemas validate numeric coordinate bounds and reject URL proxy queries', () => {
  assert.deepEqual(reverseGeocodeSchema.parse({ latitude: 90, longitude: -180 }), { latitude: 90, longitude: -180 });
  assert.throws(() => reverseGeocodeSchema.parse({ latitude: 90.1, longitude: 0 }));
  assert.throws(() => reverseGeocodeSchema.parse({ latitude: 0, longitude: -180.1 }));
  assert.throws(() => reverseGeocodeSchema.parse({ latitude: '6', longitude: 3 }));
  assert.deepEqual(locationSearchSchema.parse({ q: ' Lagos ' }), { q: 'Lagos', limit: 5 });
  assert.throws(() => locationSearchSchema.parse({ q: 'x'.repeat(121) }));
  assert.throws(() => locationSearchSchema.parse({ q: 'https://example.com' }));
  assert.throws(() => locationSearchSchema.parse({ q: 'Lagos', url: 'https://example.com' }));
});

test('location test provider abstraction returns only bounded public fields', async () => {
  let receivedCoordinates: { latitude: number; longitude: number } | null = null;
  let receivedSearch: { query: string; limit: number } | null = null;
  const provider: LocationProvider = {
    getCapabilities: () => ({ available: true, reverseGeocode: true, search: true }),
    reverseGeocode: async input => { receivedCoordinates = input; return { formattedAddress: '12 Main Street', city: 'Lagos', latitude: 6.5244, longitude: 3.3792, providerPlaceId: 'private-place-id', countryCode: 'ng' }; },
    search: async input => { receivedSearch = input; return Array.from({ length: 4 }, () => ({ city: 'Abuja', latitude: 9.0, longitude: 7.0, providerPlaceId: 'hidden' })); }
  };
  const service = new LocationService(provider, new LocationRepository());
  assert.deepEqual(service.capabilities(), { providerAvailable: true, reverseGeocodeAvailable: true, searchAvailable: true, persistentLocationSharingAvailable: false });
  const lookup = await service.reverseGeocode({ latitude: 6.5244, longitude: 3.3792 });
  assert.deepEqual(receivedCoordinates, { latitude: 6.5244, longitude: 3.3792 });
  assert.deepEqual(lookup.location, { formattedAddress: '12 Main Street', city: 'Lagos', countryCode: 'NG' });
  assert.equal(JSON.stringify(lookup).includes('latitude'), false);
  assert.equal(JSON.stringify(lookup).includes('private-place-id'), false);
  const results = await service.search({ query: 'Abuja', limit: 2 });
  assert.deepEqual(receivedSearch, { query: 'Abuja', limit: 2 });
  assert.equal(results.items.length, 2);
  assert.equal(JSON.stringify(results).includes('longitude'), false);
});

test('unavailable location provider returns no fabricated lookup or search results', async () => {
  const service = new LocationService(new UnavailableLocationProvider(), new LocationRepository());
  assert.deepEqual(service.capabilities(), { providerAvailable: false, reverseGeocodeAvailable: false, searchAvailable: false, persistentLocationSharingAvailable: false });
  await assert.rejects(() => service.reverseGeocode({ latitude: 6, longitude: 3 }), (error: unknown) => error instanceof AppError && error.code === 'SERVICE_UNAVAILABLE');
  await assert.rejects(() => service.search({ query: 'Lagos', limit: 5 }), (error: unknown) => error instanceof AppError && error.code === 'SERVICE_UNAVAILABLE');
});

test('authenticated Translation and Location routes reject unauthenticated and malformed requests and return 503 when unconfigured', async () => {
  const { repository } = translationRepository();
  const translationService = new TranslationService(new UnavailableTranslationProvider(), repository);
  const locationService = new LocationService(new UnavailableLocationProvider(), new LocationRepository());
  const app = appWithAuth(createTranslationRouter(translationService), createLocationRouter(locationService));
  await withServer(app, async baseUrl => {
    assert.equal((await fetch(`${baseUrl}/v1/translation/capabilities`)).status, 401);
    assert.equal((await fetch(`${baseUrl}/v1/location/capabilities`)).status, 401);
    const headers = { authorization: 'Bearer test-token', 'content-type': 'application/json' };
    assert.equal((await fetch(`${baseUrl}/v1/translation`, { method: 'POST', headers, body: JSON.stringify({ text: '', targetLanguage: 'fr' }) })).status, 422);
    const oversized = await fetch(`${baseUrl}/v1/translation`, { method: 'POST', headers, body: JSON.stringify({ text: 'x'.repeat(5001), targetLanguage: 'fr' }) });
    assert.equal(oversized.status, 422);
    const spoofed = await fetch(`${baseUrl}/v1/translation`, { method: 'POST', headers, body: JSON.stringify({ text: 'Hello', targetLanguage: 'fr', user_id: userB }) });
    assert.equal(spoofed.status, 422);
    const unavailableTranslation = await fetch(`${baseUrl}/v1/translation`, { method: 'POST', headers, body: JSON.stringify({ text: 'Hello', targetLanguage: 'fr' }) });
    assert.equal(unavailableTranslation.status, 503);
    assert.equal((await unavailableTranslation.text()).includes('translatedText'), false);
    const invalidLat = await fetch(`${baseUrl}/v1/location/reverse-geocode`, { method: 'POST', headers, body: JSON.stringify({ latitude: 91, longitude: 0 }) });
    assert.equal(invalidLat.status, 422);
    const invalidLon = await fetch(`${baseUrl}/v1/location/reverse-geocode`, { method: 'POST', headers, body: JSON.stringify({ latitude: 0, longitude: -181 }) });
    assert.equal(invalidLon.status, 422);
    const validButUnavailable = await fetch(`${baseUrl}/v1/location/reverse-geocode`, { method: 'POST', headers, body: JSON.stringify({ latitude: 6.5244, longitude: 3.3792 }) });
    assert.equal(validButUnavailable.status, 503);
    const spoofedLocation = await fetch(`${baseUrl}/v1/location/reverse-geocode`, { method: 'POST', headers, body: JSON.stringify({ latitude: 6.5244, longitude: 3.3792, user_id: userB }) });
    assert.equal(spoofedLocation.status, 422);
    assert.equal((await fetch(`${baseUrl}/v1/location/search?q=${encodeURIComponent('x'.repeat(121))}`, { headers })).status, 422);
    assert.equal((await fetch(`${baseUrl}/v1/location/search?q=${encodeURIComponent('https://example.com')}`, { headers })).status, 422);
    assert.equal((await fetch(`${baseUrl}/v1/location/search?q=Lagos`, { headers })).status, 503);
  });
});
