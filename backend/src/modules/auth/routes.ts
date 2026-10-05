import { Router, type RequestHandler } from 'express';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import { AppError } from '../../middleware/errors.js';
import type { AuthService } from './service.js';
import type { AccountDeletionService } from './account-deletion.js';
import type { FirebaseAuthProvider } from '../../providers/firebase-auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';

const sessionParamsSchema = z.object({ id: z.string().uuid() }).strict();
const sessionMutationLimit = createRateLimiter({ name: 'auth-session-mutation', windowMs: 60_000, max: 10 });
const sessionReadLimit = createRateLimiter({ name: 'auth-session-read', windowMs: 60_000, max: 60 });
const accountDeletionLimit = createRateLimiter({ name: 'auth-account-deletion', windowMs: 10 * 60_000, max: 6 });
const accountDeletionSchema = z.object({ confirmation: z.literal('DELETE') }).strict();

export function createFirebaseAuthenticationMiddleware(provider: FirebaseAuthProvider, authService: AuthService): RequestHandler {
  return async (request, _response, next) => {
    const header = request.header('authorization');
    if (!header) return next();
    const [scheme, token] = header.split(' ');
    if (scheme?.toLowerCase() !== 'bearer' || !token) return next(new AppError('UNAUTHORIZED', 'Invalid authorization header'));
    try {
      const identity = await provider.verifyIdentity(token);
      const result = await authService.provision(identity, {
        ipAddress: request.ip,
        userAgent: request.header('user-agent')
      });
      request.auth = result.context;
      next();
    } catch (error) {
      next(error instanceof AppError ? error : new AppError('SERVICE_UNAVAILABLE', 'Authentication is temporarily unavailable'));
    }
  };
}

export function createAuthRouter(authService: AuthService, accountDeletion?: AccountDeletionService): Router {
  const router = Router();
  if (accountDeletion) {
    router.get('/delete-account/preflight', requireAuth, accountDeletionLimit, async (request, response, next) => {
      try { sendSuccess(response, await accountDeletion.preflight(currentUserId(request))); } catch (error) { next(error); }
    });
    router.post('/delete-account', requireAuth, accountDeletionLimit, validate('body', accountDeletionSchema), async (request, response, next) => {
      try { sendSuccess(response, await accountDeletion.deleteAccount(currentUserId(request), { ipAddress: request.ip })); } catch (error) { next(error); }
    });
  }
  router.get('/sessions', requireAuth, sessionReadLimit, async (request, response, next) => {
    try {
      const sessionId = request.auth?.sessionId;
      if (!sessionId) throw new AppError('UNAUTHORIZED', 'Application session is unavailable');
      sendSuccess(response, await authService.listSessions(currentUserId(request), sessionId));
    } catch (error) { next(error); }
  });
  router.post('/sessions/revoke-all', requireAuth, sessionMutationLimit, async (request, response, next) => {
    try {
      const sessionId = request.auth?.sessionId;
      if (!sessionId) throw new AppError('UNAUTHORIZED', 'Application session is unavailable');
      sendSuccess(response, await authService.revokeAllSessions(currentUserId(request), sessionId, { ipAddress: request.ip }));
    } catch (error) { next(error); }
  });
  router.post('/sessions/:id/revoke', requireAuth, sessionMutationLimit, validate('params', sessionParamsSchema), async (request, response, next) => {
    try {
      const id = (request.params as { id: string }).id;
      await authService.revokeSession(currentUserId(request), id, { ipAddress: request.ip });
      sendSuccess(response, { revoked: true, id });
    } catch (error) { next(error); }
  });
  router.get('/me', requireAuth, (request, response) => {
    const account = request.auth?.account as { user: unknown; profile: unknown } | undefined;
    if (!account) throw new AppError('SERVICE_UNAVAILABLE', 'Authenticated account context unavailable');
    const user = account.user as { id: string; email: string | null; phone: string | null; status: string };
    sendSuccess(response, { user: { id: user.id, email: user.email, phone: user.phone, status: user.status }, profile: account.profile });
  });
  router.get('/session', requireAuth, (request, response) => {
    sendSuccess(response, { authenticated: true, userId: request.auth?.userId, sessionId: request.auth?.sessionId });
  });
  router.post('/logout', requireAuth, sessionMutationLimit, async (request, response, next) => {
    try {
      const sessionId = request.auth?.sessionId;
      if (!sessionId) throw new AppError('UNAUTHORIZED', 'Application session is unavailable');
      await authService.revokeSession(currentUserId(request), sessionId, { ipAddress: request.ip });
      sendSuccess(response, { revoked: true });
    } catch (error) {
      next(error);
    }
  });
  return router;
}
