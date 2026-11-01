import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { requireIdempotencyKey } from '../../middleware/idempotency.js';
import { validate } from '../../middleware/validate.js';
import { paginationQuerySchema } from '../../utils/pagination.js';
import { OrderService } from './service.js';
import { createOrderController } from './controller.js';
import { addressIdSchema, deliveryAddressSchema, disputeSchema, orderCreateSchema, orderFulfillmentParamsSchema, orderIdSchema, sellerFulfillmentActionSchema } from './schemas.js';

export function createOrderRouter(service: OrderService): Router {
  const router = Router();
  const controller = createOrderController(service);
  router.get('/seller', requireAuth, validate('query', paginationQuerySchema), controller.sellerOrders);
  router.post('/', requireAuth, requireIdempotencyKey, validate('body', orderCreateSchema), controller.create);
  router.get('/addresses', requireAuth, controller.addresses);
  router.post('/addresses', requireAuth, validate('body', deliveryAddressSchema), controller.createAddress);
  router.patch('/addresses/:id', requireAuth, validate('params', addressIdSchema), validate('body', deliveryAddressSchema), controller.updateAddress);
  router.delete('/addresses/:id', requireAuth, validate('params', addressIdSchema), controller.deleteAddress);
  router.get('/', requireAuth, validate('query', paginationQuerySchema), controller.list);
  router.get('/:id', requireAuth, validate('params', orderIdSchema), controller.get);
  router.patch('/:id/fulfillments/:fulfillmentId', requireAuth, validate('params', orderFulfillmentParamsSchema), validate('body', sellerFulfillmentActionSchema), controller.updateSellerFulfillment);
  router.post('/:id/fulfillments/:fulfillmentId/confirm', requireAuth, validate('params', orderFulfillmentParamsSchema), controller.confirmReceived);
  router.post('/:id/fulfillments/:fulfillmentId/disputes', requireAuth, validate('params', orderFulfillmentParamsSchema), validate('body', disputeSchema), controller.createDispute);
  return router;
}
