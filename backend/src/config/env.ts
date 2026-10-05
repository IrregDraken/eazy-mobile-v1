import 'dotenv/config';
import { z } from 'zod';

const envBoolean = z.preprocess((value) => {
  if (typeof value !== 'string') return value;
  if (value.toLowerCase() === 'true') return true;
  if (value.toLowerCase() === 'false') return false;
  return value;
}, z.boolean());

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  LOG_LEVEL: z.string().default('info'),
  DATABASE_URL: z.string().url().optional(),
  CORS_ORIGIN: z.string().default('*'),
  SUPABASE_PROJECT_REF: z.string().optional(),
  SUPABASE_URL: z.string().url().optional(),
  SUPABASE_SERVICE_ROLE_KEY: z.union([z.string().trim().min(1).max(8192), z.literal('')]).optional(),
  MEDIA_BUCKET: z.string().trim().min(1).max(63).default('eazy-media'),
  SUPABASE_DB_HOST: z.string().optional(),
  TRUST_PROXY: envBoolean.default(false),
  ENFORCE_HTTPS: envBoolean.default(false),
  DB_POOL_MAX: z.coerce.number().int().positive().max(50).default(10),
  DB_IDLE_TIMEOUT_MS: z.coerce.number().int().positive().default(30000),
  DB_CONNECTION_TIMEOUT_MS: z.coerce.number().int().positive().default(5000),
  RATE_LIMIT_WINDOW_MS: z.coerce.number().int().positive().default(60000),
  RATE_LIMIT_MAX: z.coerce.number().int().positive().default(120),
  FIREBASE_PROJECT_ID: z.string().optional(),
  FIREBASE_CLIENT_EMAIL: z.string().email().optional(),
  FIREBASE_PRIVATE_KEY: z.string().optional(),
  FIREBASE_CHECK_REVOKED: envBoolean.default(true),
  EAZY_SESSION_TTL_DAYS: z.coerce.number().int().positive().max(90).default(30),
  RESEND_API_KEY: z.union([z.string().trim().min(1).max(4096), z.literal('')]).optional(),
  RESEND_FROM_EMAIL: z.union([z.string().trim().email(), z.literal('')]).optional(),
  OTP_TTL_MINUTES: z.coerce.number().int().min(1).max(60).optional(),
  OTP_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(10).optional(),
  AI_PROVIDER_BASE_URL: z.union([z.string().trim().url(), z.literal('')]).optional(),
  AI_PROVIDER_API_KEY: z.union([z.string().trim().min(1).max(4096), z.literal('')]).optional(),
  AI_PROVIDER_MODEL: z.union([z.string().trim().min(1).max(128), z.literal('')]).optional(),
  AI_PROVIDER_TIMEOUT_MS: z.coerce.number().int().min(1000).max(30000).optional(),
  TRANSLATION_PROVIDER: z.enum(['deepl', 'google']).default('deepl'),
  TRANSLATION_PROVIDER_API_KEY: z.union([z.string().trim().min(1).max(4096), z.literal('')]).optional(),
  TRANSLATION_PROVIDER_BASE_URL: z.union([z.string().trim().url(), z.literal('')]).optional(),
  TRANSLATION_PROVIDER_TIMEOUT_MS: z.coerce.number().int().min(1000).max(30000).optional(),
  LOCATION_PROVIDER_API_KEY: z.union([z.string().trim().min(1).max(4096), z.literal('')]).optional(),
  LOCATION_GEOCODE_BASE_URL: z.union([z.string().trim().url(), z.literal('')]).optional(),
  LOCATION_SEARCH_BASE_URL: z.union([z.string().trim().url(), z.literal('')]).optional(),
  LOCATION_PROVIDER_TIMEOUT_MS: z.coerce.number().int().min(1000).max(30000).optional()
  ,PAYSTACK_ENABLED: envBoolean.optional()
  ,PAYSTACK_MODE: z.enum(['test', 'live']).optional()
  ,PAYSTACK_SECRET_KEY: z.union([z.string().trim().min(1).max(4096), z.literal('')]).optional()
  ,PAYSTACK_WEBHOOK_SECRET: z.union([z.string().trim().min(1).max(4096), z.literal('')]).optional()
  ,PAYMENT_CALLBACK_URL: z.union([z.string().trim().url(), z.literal('')]).optional()
}).superRefine((value, context) => {
  const aiFields = [
    ['AI_PROVIDER_BASE_URL', value.AI_PROVIDER_BASE_URL],
    ['AI_PROVIDER_API_KEY', value.AI_PROVIDER_API_KEY],
    ['AI_PROVIDER_MODEL', value.AI_PROVIDER_MODEL]
  ] as const;
  addCompleteProviderIssue(context, aiFields, 'AI provider configuration is incomplete. Set all of AI_PROVIDER_BASE_URL, AI_PROVIDER_API_KEY, and AI_PROVIDER_MODEL, or remove all three if Eazy Assist is disabled.');

  const translationFields = [
    ['TRANSLATION_PROVIDER_API_KEY', value.TRANSLATION_PROVIDER_API_KEY],
    ['TRANSLATION_PROVIDER_BASE_URL', value.TRANSLATION_PROVIDER_BASE_URL],
    ['TRANSLATION_PROVIDER_TIMEOUT_MS', value.TRANSLATION_PROVIDER_TIMEOUT_MS]
  ] as const;
  addOptionalProviderIssue(context, translationFields, 'Translation provider configuration is incomplete. Set TRANSLATION_PROVIDER_API_KEY with any optional overrides, or remove all translation provider settings.');

  const locationFields = [
    ['LOCATION_PROVIDER_API_KEY', value.LOCATION_PROVIDER_API_KEY],
    ['LOCATION_GEOCODE_BASE_URL', value.LOCATION_GEOCODE_BASE_URL],
    ['LOCATION_SEARCH_BASE_URL', value.LOCATION_SEARCH_BASE_URL],
    ['LOCATION_PROVIDER_TIMEOUT_MS', value.LOCATION_PROVIDER_TIMEOUT_MS]
  ] as const;
  addOptionalProviderIssue(context, locationFields, 'Location provider configuration is incomplete. Set LOCATION_PROVIDER_API_KEY with any optional overrides, or remove all location provider settings.');

  if (value.AI_PROVIDER_BASE_URL) {
    validateHttpsEndpoint(value.AI_PROVIDER_BASE_URL, 'AI_PROVIDER_BASE_URL', context);
  }
  const resendPresent = Boolean(value.RESEND_API_KEY || value.RESEND_FROM_EMAIL);
  if (resendPresent && (!value.RESEND_API_KEY || !value.RESEND_FROM_EMAIL)) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['RESEND_API_KEY'], message: 'Email verification requires both RESEND_API_KEY and RESEND_FROM_EMAIL.' });
  }
  for (const [key, endpoint] of [
    ['TRANSLATION_PROVIDER_BASE_URL', value.TRANSLATION_PROVIDER_BASE_URL],
    ['LOCATION_GEOCODE_BASE_URL', value.LOCATION_GEOCODE_BASE_URL],
    ['LOCATION_SEARCH_BASE_URL', value.LOCATION_SEARCH_BASE_URL]
  ] as const) {
    if (endpoint) validateHttpsEndpoint(endpoint, key, context);
  }
  if (value.PAYSTACK_ENABLED && !value.PAYSTACK_SECRET_KEY) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['PAYSTACK_SECRET_KEY'], message: 'Paystack is enabled but PAYSTACK_SECRET_KEY is missing.' });
  }
  if (value.PAYSTACK_WEBHOOK_SECRET && !value.PAYSTACK_SECRET_KEY) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['PAYSTACK_WEBHOOK_SECRET'], message: 'PAYSTACK_WEBHOOK_SECRET requires PAYSTACK_SECRET_KEY.' });
  }
  if (value.PAYMENT_CALLBACK_URL) validateHttpsEndpoint(value.PAYMENT_CALLBACK_URL, 'PAYMENT_CALLBACK_URL', context);
  if (value.NODE_ENV === 'production') {
    if (!value.DATABASE_URL) context.addIssue({ code: z.ZodIssueCode.custom, path: ['DATABASE_URL'], message: 'Production requires DATABASE_URL.' });
    if (!value.SUPABASE_URL || !value.SUPABASE_SERVICE_ROLE_KEY) context.addIssue({ code: z.ZodIssueCode.custom, path: ['SUPABASE_URL'], message: 'Production requires Supabase URL and backend-only service role key for durable media.' });
    if (!value.FIREBASE_PROJECT_ID || !value.FIREBASE_CLIENT_EMAIL || !value.FIREBASE_PRIVATE_KEY) context.addIssue({ code: z.ZodIssueCode.custom, path: ['FIREBASE_PROJECT_ID'], message: 'Production requires all Firebase Admin credentials.' });
    if (!value.CORS_ORIGIN || value.CORS_ORIGIN === '*') context.addIssue({ code: z.ZodIssueCode.custom, path: ['CORS_ORIGIN'], message: 'Production requires an explicit CORS_ORIGIN; wildcard CORS is not allowed.' });
    if (!value.ENFORCE_HTTPS) context.addIssue({ code: z.ZodIssueCode.custom, path: ['ENFORCE_HTTPS'], message: 'Production requires ENFORCE_HTTPS=true.' });
    if (!value.TRUST_PROXY) context.addIssue({ code: z.ZodIssueCode.custom, path: ['TRUST_PROXY'], message: 'Production behind a TLS-terminating proxy requires TRUST_PROXY=true.' });
  }
});

export type AppConfig = z.infer<typeof envSchema>;

type ConfigIssueContext = z.RefinementCtx;
type ConfigField = readonly [string, unknown];

function addCompleteProviderIssue(context: ConfigIssueContext, fields: readonly ConfigField[], message: string) {
  const firstField = fields[0];
  if (!firstField) return;
  const present = fields.filter(([, value]) => value !== undefined && value !== '').length;
  if (present > 0 && present < fields.length) {
    const firstPresent = fields.find(([, value]) => value !== undefined && value !== '');
    context.addIssue({ code: z.ZodIssueCode.custom, path: [firstPresent?.[0] ?? firstField[0]], message });
  }
}

function addOptionalProviderIssue(context: ConfigIssueContext, fields: readonly ConfigField[], message: string) {
  const credentialField = fields[0];
  if (!credentialField) return;
  const present = fields.filter(([, value]) => value !== undefined && value !== '').length;
  const credentialPresent = credentialField[1] !== undefined && credentialField[1] !== '';
  if (present > 0 && !credentialPresent) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: [credentialField[0]], message });
  }
}

function validateHttpsEndpoint(endpoint: string, key: string, context: ConfigIssueContext) {
  const url = new URL(endpoint);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: [key], message: 'Provider endpoint must be an HTTPS URL without credentials, query, or fragment' });
  }
}

export function loadConfig(source: NodeJS.ProcessEnv = process.env): AppConfig {
  const result = envSchema.safeParse(source);
  if (!result.success) {
    throw new Error(`Invalid environment configuration: ${result.error.message}`);
  }
  return result.data;
}
