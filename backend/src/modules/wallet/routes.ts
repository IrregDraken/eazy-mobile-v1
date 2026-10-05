import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { createWalletSchema, transferSchema, walletPaginationSchema, walletTransactionParamsSchema } from './schemas.js';
import { createWalletController } from './controller.js';
import type { WalletService } from './service.js';

export function createWalletRouter(service: WalletService): Router {
  const router = Router();
  const controller = createWalletController(service);
  const rateLimit = createRateLimiter({ name: 'wallet-transfer', windowMs: 60_000, max: 10 });
  router.use(requireAuth);
  router.get('/', controller.getWallet);
  router.post('/', validate('body', createWalletSchema), controller.createWallet);
  router.get('/transactions', validate('query', walletPaginationSchema), controller.listTransactions);
  router.get('/transactions/:id', validate('params', walletTransactionParamsSchema), controller.getTransaction);
  router.post('/transfers', rateLimit, validate('body', transferSchema), controller.transfer);
  return router;
}
