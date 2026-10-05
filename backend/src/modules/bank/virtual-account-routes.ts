import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { virtualAccountAssignSchema } from './virtual-account-schemas.js';
import { createVirtualAccountController } from './virtual-account-controller.js';
import type { VirtualAccountService } from './virtual-account-service.js';

export function createVirtualAccountRouter(service: VirtualAccountService): Router {
  const router = Router();
  const controller = createVirtualAccountController(service);
  const mutationLimit = createRateLimiter({ name: 'virtual-account-mutation', windowMs: 60_000, max: 3 });
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.get('/', controller.get);
  router.post('/', mutationLimit, validate('body', virtualAccountAssignSchema), controller.assign);
  return router;
}