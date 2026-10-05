import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { requireIdempotencyKey } from '../../middleware/idempotency.js';
import { validate } from '../../middleware/validate.js';
import { paymentIdParamsSchema, paymentInitializationSchema } from './schemas.js';
import { createPaymentController } from './controller.js';
import type { PaymentService } from './service.js';
import { AppError } from '../../middleware/errors.js';
import type { VirtualAccountService } from '../bank/virtual-account-service.js';

export function createPaymentRouter(service: PaymentService, virtualAccounts?: VirtualAccountService): Router {
  const router = Router();
  const controller = createPaymentController(service);
  const mutationLimit = createRateLimiter({ name: 'payment-mutation', windowMs: 60_000, max: 5 });
  router.get('/callback', async (request, response, next) => {
    try {
      const reference = typeof request.query.reference === 'string' ? request.query.reference.trim() : '';
      if (!reference || reference.length > 255) throw new AppError('BAD_REQUEST', 'Missing payment reference');
      const result = await service.handleWebhook(reference);
      const transactionId = result.transactionId;
      const deepLink = transactionId ? 'eazy://wallet?payment=' + encodeURIComponent(transactionId) : 'eazy://wallet';
      return response.redirect(303, deepLink);
    } catch (error) { return next(error); }
  });
  router.post('/webhook', async (request, response, next) => {
    try {
      if (!service.verifyWebhookSignature(request.rawBody ?? JSON.stringify(request.body), request.header('x-paystack-signature'))) {
        throw new AppError('UNAUTHORIZED', 'Invalid payment webhook signature');
      }
      const event = request.body as { event?: string; data?: { reference?: string } };
      const reference = event.data?.reference?.trim();
      if (event.event === 'charge.success' && reference) {
        await service.handleWebhook(reference);
        if (virtualAccounts) await virtualAccounts.handleWebhook(event.event, event.data as Record<string, any>);
      }
      if (virtualAccounts && event.event?.startsWith('dedicatedaccount.')) await virtualAccounts.handleWebhook(event.event, event.data as Record<string, any>);
      response.status(202).json({ success: true, data: { accepted: true }, meta: {} });
    } catch (error) { next(error); }
  });
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.post('/initialize', mutationLimit, requireIdempotencyKey, validate('body', paymentInitializationSchema), controller.initialize);
  router.get('/:id', validate('params', paymentIdParamsSchema), controller.get);
  router.post('/:id/verify', mutationLimit, validate('params', paymentIdParamsSchema), controller.verify);
  return router;
}
