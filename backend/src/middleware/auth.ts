import type { Request, RequestHandler } from 'express';
import { AppError } from './errors.js';

export interface AuthContext {
  userId: string;
  firebaseUid?: string;
  sessionId?: string;
  provider: string;
  claims: Record<string, unknown>;
  account?: unknown;
}

export interface Authenticator {
  authenticate(token: string): Promise<AuthContext>;
}

export const optionalAuth: RequestHandler = (_request, _response, next) => next();

export const requireAuth: RequestHandler = (request, _response, next) => {
  if (!request.auth) {
    next(new AppError('UNAUTHORIZED', 'Authentication required'));
    return;
  }
  next();
};

export function requireRole(...roles: string[]): RequestHandler {
  return (request, _response, next) => {
    const role = request.auth?.claims.role;
    if (!request.auth) return next(new AppError('UNAUTHORIZED', 'Authentication required'));
    if (typeof role !== 'string' || !roles.includes(role)) return next(new AppError('FORBIDDEN', 'Insufficient permissions'));
    next();
  };
}

export function currentUserId(request: Request): string {
  if (!request.auth) throw new AppError('UNAUTHORIZED', 'Authentication required');
  return request.auth.userId;
}

export function createAuthenticationMiddleware(authenticator: Authenticator): RequestHandler {
  return async (request, _response, next) => {
    const header = request.header('authorization');
    if (!header) return next();
    const [scheme, token] = header.split(' ');
    if (scheme?.toLowerCase() !== 'bearer' || !token) return next(new AppError('UNAUTHORIZED', 'Invalid authorization header'));
    try {
      request.auth = await authenticator.authenticate(token);
      next();
    } catch (error) {
      next(error instanceof AppError ? error : new AppError('UNAUTHORIZED', 'Invalid authentication'));
    }
  };
}
