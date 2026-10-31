import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { AppError } from '../../middleware/errors.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { requireIdempotencyKey } from '../../middleware/idempotency.js';
import { validate } from '../../middleware/validate.js';
import type { WalletService } from '../wallet/service.js';
import { qrCreateSchema, qrIdSchema, qrPaymentSchema, qrResolveSchema } from './schemas.js';
import { createQrController } from './controller.js';
import type { QrService } from './service.js';
import type { PaymentPinService } from '../wallet/payment-pin-service.js';
import { requirePaymentPin } from '../wallet/payment-pin-middleware.js';

export function createQrRouter(qrService: QrService, walletService: WalletService, paymentPin?: PaymentPinService): Router {
  const router = Router();
  const controller = createQrController(qrService, walletService);
  const payLimit = createRateLimiter({ name: 'qr-payment', windowMs: 60_000, max: 10 });
  router.use(requireAuth);
  router.post('/', validate('body', qrCreateSchema), controller.create);
  router.post('/resolve', validate('body', qrResolveSchema), controller.resolve);
  router.delete('/:id', validate('params', qrIdSchema), controller.revoke);
  if (paymentPin) {
    router.post('/pay', payLimit, validate('body', qrPaymentSchema), requireIdempotencyKey, requirePaymentPin(paymentPin), controller.pay);
  } else {
    router.post('/pay', payLimit, validate('body', qrPaymentSchema), requireIdempotencyKey, (_request, _response, next) => {
      next(new AppError('SERVICE_UNAVAILABLE', 'Payment PIN authorization is unavailable'));
    });
  }
  return router;
}
