import type { ErrorRequestHandler, RequestHandler } from 'express';
import { sendError } from '../utils/http.js';
import { safeErrorSummary } from '../config/redaction.js';

export type ErrorCode =
  | 'BAD_REQUEST'
  | 'UNAUTHORIZED'
  | 'FORBIDDEN'
  | 'NOT_FOUND'
  | 'CONFLICT'
  | 'VALIDATION_ERROR'
  | 'RATE_LIMITED'
  | 'INTERNAL_ERROR'
  | 'SERVICE_UNAVAILABLE';

const statusByCode: Record<ErrorCode, number> = {
  BAD_REQUEST: 400, UNAUTHORIZED: 401, FORBIDDEN: 403, NOT_FOUND: 404, CONFLICT: 409,
  VALIDATION_ERROR: 422, RATE_LIMITED: 429, INTERNAL_ERROR: 500, SERVICE_UNAVAILABLE: 503
};

export class AppError extends Error {
  constructor(
    public readonly code: ErrorCode,
    message: string,
    public readonly details: unknown = {},
    public readonly statusCode = statusByCode[code]
  ) {
    super(message);
    this.name = 'AppError';
  }
}

export const notFoundHandler: RequestHandler = (request, response) => {
  sendError(response, request.id, { code: 'NOT_FOUND', message: `Route ${request.method} ${request.path} not found` }, 404);
};

export function toAppError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  return new AppError('INTERNAL_ERROR', 'An unexpected error occurred');
}

export function errorHandler(logger: { error: (obj: unknown, message?: string) => void }): ErrorRequestHandler {
  return (error, request, response, next) => {
    if (response.headersSent) return next(error);
    const appError = toAppError(error);
    logger.error({
      event: 'request.failed', requestId: request.id, method: request.method,
      path: request.path, statusCode: appError.statusCode, errorCode: appError.code,
      error: appError.code === 'INTERNAL_ERROR' ? safeErrorSummary(error) : undefined,
      userId: request.auth?.userId
    }, 'request failed');
    sendError(response, request.id, appError, appError.statusCode);
  };
}
