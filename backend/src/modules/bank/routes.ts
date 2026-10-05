import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { bankListSchema, bankResolveSchema } from './schemas.js';
import { createBankController } from './controller.js';
import type { BankService } from './service.js';
export function createBankRouter(service: BankService): Router {
  const router = Router();
  const controller = createBankController(service);
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.get('/', validate('query', bankListSchema), controller.listBanks);
  router.post('/resolve', validate('body', bankResolveSchema), controller.resolveAccount);
  return router;
}
