import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { AppError } from '../../middleware/errors.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import type { EmailVerificationService } from './email-verification.js';
import type { FirebaseAuthProvider } from '../../providers/firebase-auth.js';

const requestSchema = z.object({ email: z.string().trim().email() }).strict();
const verifySchema = z.object({ challengeId: z.string().uuid(), code: z.string().trim().regex(/^\d{6}$/) }).strict();
const requestLimit = createRateLimiter({ name: 'email-verification-request', windowMs: 10 * 60_000, max: 5 });
const verifyLimit = createRateLimiter({ name: 'email-verification-verify', windowMs: 10 * 60_000, max: 20 });

export function createEmailVerificationRouter(service: EmailVerificationService, firebaseProvider: FirebaseAuthProvider): Router {
  const router = Router();

  router.post('/email-verification/request-code', requestLimit, validate('body', requestSchema), async (request, response, next) => {
    try {
      sendSuccess(response, await service.requestCode((request.body as { email: string }).email));
    } catch (error) { next(error); }
  });

  router.post('/email-verification/verify-code', verifyLimit, validate('body', verifySchema), async (request, response, next) => {
    try {
      const header = request.header('authorization');
      if (!header) throw new AppError('UNAUTHORIZED', 'Firebase authentication is required');
      const [scheme, token] = header.split(' ');
      if (scheme?.toLowerCase() !== 'bearer' || !token) throw new AppError('UNAUTHORIZED', 'Invalid authorization header');

      const identity = await firebaseProvider.verifyIdentity(token);
      const body = request.body as { challengeId: string; code: string };
      const result = await service.verifyCode(body.challengeId, body.code);
      const firebaseEmail = typeof identity.claims.email === 'string' ? identity.claims.email.trim().toLowerCase() : '';
      if (!firebaseEmail || firebaseEmail !== result.email) {
        throw new AppError('FORBIDDEN', 'Verification request does not match the authenticated account');
      }

      await firebaseProvider.markEmailVerified(identity.firebaseUid);
      sendSuccess(response, { challengeId: result.challengeId, verified: true });
    } catch (error) { next(error); }
  });

  return router;
}
