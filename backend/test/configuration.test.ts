import assert from 'node:assert/strict';
import test from 'node:test';
import { loadConfig } from '../src/config/env.js';
import { OpenAICompatibleProvider } from '../src/modules/assist/providers/openai-compatible.js';
import { GoogleCloudTranslationProvider } from '../src/modules/translation/providers/google-cloud.js';
import { HereLocationProvider } from '../src/modules/location/providers/here.js';
import { UnavailableAIProvider } from '../src/modules/assist/providers/unavailable.js';

const core = {
  NODE_ENV: 'production',
  PORT: '3000',
  LOG_LEVEL: 'silent',
  DATABASE_URL: 'postgresql://localhost:5432/eazy',
  SUPABASE_URL: 'https://eazy-test.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'synthetic-test-service-role-key',
  CORS_ORIGIN: 'https://eazy.test',
  ENFORCE_HTTPS: 'true',
  TRUST_PROXY: 'true',
  FIREBASE_PROJECT_ID: 'eazy-production',
  FIREBASE_CLIENT_EMAIL: 'firebase-adminsdk@example.com',
  FIREBASE_PRIVATE_KEY: 'test-private-key'
} satisfies NodeJS.ProcessEnv;

test('minimum production configuration parses with optional providers disabled', () => {
  const config = loadConfig(core);
  assert.equal(config.NODE_ENV, 'production');
  assert.equal(config.DATABASE_URL, core.DATABASE_URL);
  assert.equal(config.AI_PROVIDER_BASE_URL, undefined);
  assert.equal(config.TRANSLATION_PROVIDER_API_KEY, undefined);
  assert.equal(config.LOCATION_PROVIDER_API_KEY, undefined);
  assert.equal(new UnavailableAIProvider().getCapabilities().available, false);
});

test('complete AI configuration parses and selects an available provider contract', () => {
  const config = loadConfig({
    ...core,
    AI_PROVIDER_BASE_URL: 'https://generativelanguage.googleapis.com/v1beta/openai/',
    AI_PROVIDER_API_KEY: 'test-ai-key',
    AI_PROVIDER_MODEL: 'test-model'
  });
  assert.equal(config.AI_PROVIDER_MODEL, 'test-model');
  assert.equal(new OpenAICompatibleProvider(config).getCapabilities().available, true);
});

test('partial AI configuration fails with an actionable error', () => {
  assert.throws(
    () => loadConfig({ ...core, AI_PROVIDER_BASE_URL: 'https://example.com/v1/' }),
    (error: unknown) => error instanceof Error
      && error.message.includes('AI provider configuration is incomplete')
      && error.message.includes('AI_PROVIDER_API_KEY')
      && error.message.includes('remove all three')
  );
});

test('translation and location provider overrides require their credentials', () => {
  assert.throws(
    () => loadConfig({ ...core, TRANSLATION_PROVIDER_BASE_URL: 'https://example.com/translate' }),
    (error: unknown) => error instanceof Error && error.message.includes('Translation provider configuration is incomplete')
  );
  assert.throws(
    () => loadConfig({ ...core, LOCATION_PROVIDER_TIMEOUT_MS: '5000' }),
    (error: unknown) => error instanceof Error && error.message.includes('Location provider configuration is incomplete')
  );
});

test('complete optional translation and location configurations parse', () => {
  const config = loadConfig({
    ...core,
    TRANSLATION_PROVIDER_API_KEY: 'translation-key',
    TRANSLATION_PROVIDER_BASE_URL: 'https://translation.googleapis.com/language/translate/v2',
    LOCATION_PROVIDER_API_KEY: 'here-key',
    LOCATION_PROVIDER_TIMEOUT_MS: '12000'
  });
  assert.equal(config.TRANSLATION_PROVIDER_API_KEY, 'translation-key');
  assert.equal(config.LOCATION_PROVIDER_TIMEOUT_MS, 12000);
  assert.equal(new GoogleCloudTranslationProvider(config).getCapabilities().available, true);
  assert.equal(new HereLocationProvider(config).getCapabilities().available, true);
});

test('blank optional translation and location URLs select provider defaults', () => {
  const config = loadConfig({
    ...core,
    TRANSLATION_PROVIDER_API_KEY: 'translation-key',
    TRANSLATION_PROVIDER_BASE_URL: '',
    LOCATION_PROVIDER_API_KEY: 'here-key',
    LOCATION_GEOCODE_BASE_URL: '',
    LOCATION_SEARCH_BASE_URL: ''
  });
  const translation = new GoogleCloudTranslationProvider(config) as unknown as { baseUrl: URL };
  const location = new HereLocationProvider(config) as unknown as { geocodeBase: URL; searchBase: URL };

  assert.equal(translation.baseUrl.href, 'https://translation.googleapis.com/language/translate/v2');
  assert.equal(location.geocodeBase.href, 'https://geocode.search.hereapi.com/v1');
  assert.equal(location.searchBase.href, 'https://discover.search.hereapi.com/v1');
});
