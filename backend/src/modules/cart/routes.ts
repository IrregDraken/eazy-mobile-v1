import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { CartService } from './service.js';
import { createCartController } from './controller.js';
import { cartItemSchema, cartProductParamSchema, cartQuantitySchema } from './schemas.js';

export function createCartRouter(service: CartService): Router {
  const router = Router();
  const controller = createCartController(service);
  router.get('/', requireAuth, controller.get);
  router.post('/items', requireAuth, validate('body', cartItemSchema), controller.addItem);
  router.patch('/items/:productId', requireAuth, validate('params', cartProductParamSchema), validate('body', cartQuantitySchema), controller.updateItem);
  router.delete('/items/:productId', requireAuth, validate('params', cartProductParamSchema), controller.removeItem);
  router.delete('/', requireAuth, controller.clear);
  return router;
}
