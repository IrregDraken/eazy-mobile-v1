import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { paginationQuerySchema } from '../../utils/pagination.js';
import { OrderService } from './service.js';
import { createOrderController } from './controller.js';
import { orderIdSchema } from './schemas.js';

export function createOrderRouter(service: OrderService): Router {
  const router = Router();
  const controller = createOrderController(service);
  router.post('/', requireAuth, controller.create);
  router.get('/', requireAuth, validate('query', paginationQuerySchema), controller.list);
  router.get('/:id', requireAuth, validate('params', orderIdSchema), controller.get);
  return router;
}
