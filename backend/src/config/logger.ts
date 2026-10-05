import pino from 'pino';
import type { AppConfig } from './env.js';
import { sensitiveLogFields } from './redaction.js';

export function createLogger(config: AppConfig) {
  return pino({
    level: config.LOG_LEVEL,
    base: undefined,
    redact: {
      paths: sensitiveLogFields.flatMap(field => [field, `*.${field}`, `**.${field}`]),
      censor: '[REDACTED]'
    },
    serializers: {
      error: pino.stdSerializers.err
    }
  });
}
