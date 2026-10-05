import type { Response } from 'express';

export function sendSuccess<T>(response: Response, data: T, meta: Record<string, unknown> = {}) {
  return response.json({ success: true, data, meta });
}

export function sendError(response: Response, requestId: string, error: { code: string; message: string; details?: unknown }, statusCode: number) {
  return response.status(statusCode).json({
    success: false,
    error: { code: error.code, message: error.message, details: error.details ?? {} },
    requestId
  });
}
