import assert from 'node:assert/strict';
import test from 'node:test';
import { GoogleCloudTranslationProvider } from '../src/modules/translation/providers/google-cloud.js';
import { HereLocationProvider } from '../src/modules/location/providers/here.js';

const originalFetch = globalThis.fetch;

test.afterEach(() => { globalThis.fetch = originalFetch; });

test('Google translation adapter maps a real v2-shaped response', async () => {
  let requested: Request | undefined;
  globalThis.fetch = async (input, init) => {
    requested = new Request(input, init);
    return new Response(JSON.stringify({ data: { translations: [{ translatedText: 'Bonjour' }] } }), { status: 200 });
  };
  const provider = new GoogleCloudTranslationProvider({ TRANSLATION_PROVIDER_API_KEY: 'test-key', TRANSLATION_PROVIDER_TIMEOUT_MS: 1000 });
  const result = await provider.translate({ text: 'Hello', source: 'en', target: 'fr' });
  assert.equal(result.text, 'Bonjour');
  assert.equal(new URL(requested!.url).searchParams.get('key'), 'test-key');
  assert.match(requested!.url, /translation\.googleapis\.com/);
});

test('Google translation adapter normalizes malformed and upstream responses', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ data: { translations: [] } }), { status: 200 });
  await assert.rejects(() => new GoogleCloudTranslationProvider({ TRANSLATION_PROVIDER_API_KEY: 'test-key' }).translate({ text: 'Hello', target: 'fr' }), /unavailable/i);
  globalThis.fetch = async () => new Response('rate limited', { status: 429 });
  await assert.rejects(() => new GoogleCloudTranslationProvider({ TRANSLATION_PROVIDER_API_KEY: 'test-key' }).translate({ text: 'Hello', target: 'fr' }), /unavailable/i);
});

test('HERE adapter maps search and reverse-geocode public fields', async () => {
  const urls: string[] = [];
  globalThis.fetch = async (input, init) => {
    const request = new Request(input, init); urls.push(request.url);
    const reverse = request.url.includes('/revgeocode');
    return new Response(JSON.stringify({ items: [{ id: 'here-id', address: { label: 'Lagos, Nigeria', city: 'Lagos', state: 'Lagos', countryName: 'Nigeria', countryCode: 'NGA' }, position: { lat: 6.52, lng: 3.38 } }] }), { status: 200 });
  };
  const provider = new HereLocationProvider({ LOCATION_PROVIDER_API_KEY: 'here-key', LOCATION_PROVIDER_TIMEOUT_MS: 1000 });
  const search = await provider.search({ query: 'Lagos', limit: 5 });
  const reverse = await provider.reverseGeocode({ latitude: 6.52, longitude: 3.38 });
  assert.equal(search[0]?.formattedAddress, 'Lagos, Nigeria');
  assert.equal(reverse.city, 'Lagos');
  assert.ok(urls.every(url => url.includes('apiKey=here-key')));
});

test('HERE adapter normalizes malformed and upstream responses', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ items: [{ foo: 'bar' }] }), { status: 200 });
  await assert.rejects(() => new HereLocationProvider({ LOCATION_PROVIDER_API_KEY: 'here-key' }).search({ query: 'Lagos', limit: 5 }), /unavailable/i);
  globalThis.fetch = async () => new Response('down', { status: 503 });
  await assert.rejects(() => new HereLocationProvider({ LOCATION_PROVIDER_API_KEY: 'here-key' }).reverseGeocode({ latitude: 6, longitude: 3 }), /unavailable/i);
});
