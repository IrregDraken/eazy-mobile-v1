const SENSITIVE_FIELDS = new Set([
  'authorization',
  'token',
  'accesstoken',
  'refreshtoken',
  'idtoken',
  'password',
  'passwordhash',
  'pin',
  'verificationcode',
  'secret',
  'privatekey',
  'clientsecret',
  'apikey',
  'pushtoken',
  'sessiontoken',
  'cookie',
  'paymentcredentials',
  'cardnumber',
  'cvv'
]);

export const REDACTED_VALUE = '[REDACTED]';

export function isSensitiveField(field: string): boolean {
  return SENSITIVE_FIELDS.has(field.replace(/[-_]/g, '').toLowerCase());
}

export function redactSensitive<T>(value: T): T {
  return redactValue(value) as T;
}

function redactValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(redactValue);
  if (!value || typeof value !== 'object') return value;
  if (value instanceof Error) return { name: value.name, message: value.message };

  const result: Record<string, unknown> = {};
  for (const [key, child] of Object.entries(value)) {
    result[key] = isSensitiveField(key) ? REDACTED_VALUE : redactValue(child);
  }
  return result;
}

export function safeErrorSummary(error: unknown): { name: string; message: string } {
  if (error instanceof Error) return { name: error.name, message: error.message };
  return { name: 'UnknownError', message: 'Unknown error' };
}

export const sensitiveLogFields = [
  'authorization', 'token', 'accessToken', 'refreshToken', 'idToken', 'password', 'passwordHash',
  'pin', 'verificationCode', 'secret', 'privateKey', 'clientSecret', 'apiKey', 'pushToken',
  'sessionToken', 'cookie', 'paymentCredentials', 'cardNumber', 'cvv'
] as const;
