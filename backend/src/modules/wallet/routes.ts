import { Router } from 'express';
import { z } from 'zod';
import { sendSuccess } from '../../utils/http.js';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { AppError } from '../../middleware/errors.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { createWalletSchema, transferSchema, walletPaginationSchema, walletTransactionParamsSchema } from './schemas.js';
import { createWalletController } from './controller.js';
import type { WalletService } from './service.js';
import type { PaymentPinService } from './payment-pin-service.js';
import { requirePaymentPin } from './payment-pin-middleware.js';

export function createWalletRouter(service: WalletService, paymentPin?: PaymentPinService): Router {
  const router = Router();
  const controller = createWalletController(service);
  const rateLimit = createRateLimiter({ name: 'wallet-transfer', windowMs: 60_000, max: 10 });
  const pinMutationLimit = createRateLimiter({ name: 'wallet-payment-pin', windowMs: 10 * 60_000, max: 5 });
  const setupPinSchema = z.object({ pin: z.string().regex(/^\d{6}$/), confirmation: z.string().regex(/^\d{6}$/) }).strict();
  const changePinSchema = z.object({
    currentPin: z.string().regex(/^\d{6}$/),
    newPin: z.string().regex(/^\d{6}$/),
    confirmation: z.string().regex(/^\d{6}$/)
  }).strict();
  router.use(requireAuth);
  router.get('/', controller.getWallet);
  router.post('/', validate('body', createWalletSchema), controller.createWallet);
  router.get('/transactions', validate('query', walletPaginationSchema), controller.listTransactions);
  router.get('/transactions/:id', validate('params', walletTransactionParamsSchema), controller.getTransaction);
  if (paymentPin) {
    router.get('/payment-pin/status', async (request, response, next) => {
      try { sendSuccess(response, await paymentPin.status(currentUserId(request))); }
      catch (error) { next(error); }
    });
    router.post('/payment-pin/setup', pinMutationLimit, validate('body', setupPinSchema), async (request, response, next) => {
      try {
        requireRecentAuthentication(request);
        const body = request.body as { pin: string; confirmation: string };
        sendSuccess(response, await paymentPin.setup(currentUserId(request), body.pin, body.confirmation));
      } catch (error) { next(error); }
    });
    router.post('/payment-pin/change', pinMutationLimit, validate('body', changePinSchema), async (request, response, next) => {
      try {
        requireRecentAuthentication(request);
        const body = request.body as { currentPin: string; newPin: string; confirmation: string };
        sendSuccess(response, await paymentPin.change(currentUserId(request), body.currentPin, body.newPin, body.confirmation));
      } catch (error) { next(error); }
    });
    router.post('/transfers', rateLimit, requirePaymentPin(paymentPin), validate('body', transferSchema), controller.transfer);
  } else {
    router.post('/transfers', rateLimit, validate('body', transferSchema), controller.transfer);
  }
  return router;
}


function requireRecentAuthentication(request: import('express').Request) {
  const authTime = Number(request.auth?.claims.auth_time);
  const ageSeconds = Date.now() / 1000 - authTime;
  if (!Number.isFinite(authTime) || ageSeconds < 0 || ageSeconds > 300) {
    throw new AppError(
      'FORBIDDEN',
      'For security, sign in again before creating or changing your payment PIN.'
    );
  }
}
