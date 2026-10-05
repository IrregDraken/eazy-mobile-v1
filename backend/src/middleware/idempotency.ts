import type { RequestHandler } from 'express';
import type { Request } from 'express';
import { z } from 'zod';
import { AppError } from './errors.js';

const keySchema = z.string().trim().min(8).max(255);

export interface IdempotencyRecord {
  key: string;
  userId: string;
  requestHash: string;
  statusCode: number;
  responseBody: unknown;
}

export interface IdempotencyStore {
  get(key: string, userId: string): Promise<IdempotencyRecord | null>;
  save(record: IdempotencyRecord): Promise<void>;
}

export function idempotencyKey(request: Request): string {
  const value = request.header('idempotency-key');
  const parsed = keySchema.safeParse(value);
  if (!parsed.success) throw new AppError('VALIDATION_ERROR', 'A valid Idempotency-Key header is required');
  return parsed.data;
}

export const requireIdempotencyKey: RequestHandler = (request, _response, next) => {
  try { idempotencyKey(request); next(); } catch (error) { next(error); }
};
