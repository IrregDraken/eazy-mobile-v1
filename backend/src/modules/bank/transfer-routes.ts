import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { requireIdempotencyKey } from '../../middleware/idempotency.js';
import { validate } from '../../middleware/validate.js';
import { AppError } from '../../middleware/errors.js';
import { bankTransferParamsSchema, bankTransferSchema } from './transfer-schemas.js';
import { createBankTransferController } from './transfer-controller.js';
import type { BankTransferService } from './transfer-service.js';
import type { VirtualAccountService } from './virtual-account-service.js';
import type { PaymentPinService } from '../wallet/payment-pin-service.js';
import { requirePaymentPin } from '../wallet/payment-pin-middleware.js';

export function createBankTransferRouter(service: BankTransferService, virtualAccounts?: VirtualAccountService, paymentPin?: PaymentPinService): Router {
  const router = Router();
  const controller = createBankTransferController(service, virtualAccounts);
  const mutationLimit = createRateLimiter({ name: 'bank-transfer-mutation', windowMs: 60_000, max: 5 });

  router.post('/webhook', async (request, response, next) => {
    try {
      if (!service.verifyWebhookSignature(request.rawBody ?? JSON.stringify(request.body), request.header('x-paystack-signature'))) {
        throw new AppError('UNAUTHORIZED', 'Invalid bank transfer webhook signature');
      }
      return controller.webhook(request, response, next);
    } catch (error) { next(error); }
  });

  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  if (paymentPin) {
    router.post('/', mutationLimit, requireIdempotencyKey, requirePaymentPin(paymentPin), validate('body', bankTransferSchema), controller.initiate);
  } else {
    router.post('/', mutationLimit, requireIdempotencyKey, validate('body', bankTransferSchema), (_request, _response, next) => {
      next(new AppError('SERVICE_UNAVAILABLE', 'Payment PIN authorization is unavailable'));
    });
  }
  router.get('/:id', validate('params', bankTransferParamsSchema), controller.get);
  return router;
}