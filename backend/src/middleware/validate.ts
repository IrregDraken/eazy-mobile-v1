import type { RequestHandler } from 'express';
import type { z } from 'zod';
import { AppError } from './errors.js';

type RequestPart = 'params' | 'query' | 'body' | 'headers';

export function validate(part: RequestPart, schema: z.ZodTypeAny): RequestHandler {
  return (request, _response, next) => {
    const result = schema.safeParse(request[part]);
    if (!result.success) {
      next(new AppError('VALIDATION_ERROR', 'Invalid request', result.error.flatten()));
      return;
    }
    Object.defineProperty(request, part, { value: result.data, configurable: true, enumerable: true, writable: true });
    next();
  };
}
