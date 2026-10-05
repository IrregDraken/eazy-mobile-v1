import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import type { WalletService } from '../wallet/service.js';
import { qrCreateSchema, qrIdSchema, qrPaymentSchema, qrResolveSchema } from './schemas.js';
import { createQrController } from './controller.js';
import type { QrService } from './service.js';

export function createQrRouter(qrService: QrService, walletService: WalletService): Router {
  const router = Router();
  const controller = createQrController(qrService, walletService);
  const payLimit = createRateLimiter({ name: 'qr-payment', windowMs: 60_000, max: 10 });
  router.use(requireAuth);
  router.post('/', validate('body', qrCreateSchema), controller.create);
  router.post('/resolve', validate('body', qrResolveSchema), controller.resolve);
  router.delete('/:id', validate('params', qrIdSchema), controller.revoke);
  router.post('/pay', payLimit, validate('body', qrPaymentSchema), controller.pay);
  return router;
}
