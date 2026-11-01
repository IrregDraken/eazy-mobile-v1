import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { requireIdempotencyKey } from '../../middleware/idempotency.js';
import { validate } from '../../middleware/validate.js';
import { paginationQuerySchema } from '../../utils/pagination.js';
import { OrderService } from './service.js';
import { createOrderController } from './controller.js';
import { addressIdSchema, deliveryAddressSchema, orderCreateSchema, orderIdSchema } from './schemas.js';

export function createOrderRouter(service: OrderService): Router {
  const router = Router();
  const controller = createOrderController(service);
  router.post('/', requireAuth, requireIdempotencyKey, validate('body', orderCreateSchema), controller.create);
  router.get('/addresses', requireAuth, controller.addresses);
  router.post('/addresses', requireAuth, validate('body', deliveryAddressSchema), controller.createAddress);
  router.patch('/addresses/:id', requireAuth, validate('params', addressIdSchema), validate('body', deliveryAddressSchema), controller.updateAddress);
  router.delete('/addresses/:id', requireAuth, validate('params', addressIdSchema), controller.deleteAddress);
  router.get('/', requireAuth, validate('query', paginationQuerySchema), controller.list);
  router.get('/:id', requireAuth, validate('params', orderIdSchema), controller.get);
  return router;
}
