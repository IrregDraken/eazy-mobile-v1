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

export function createBankTransferRouter(service: BankTransferService, virtualAccounts?: VirtualAccountService): Router {
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
  router.post('/', mutationLimit, requireIdempotencyKey, validate('body', bankTransferSchema), controller.initiate);
  router.get('/:id', validate('params', bankTransferParamsSchema), controller.get);
  return router;
}