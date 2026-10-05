import { Router } from 'express';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { MarketplaceService, inventorySchema, productCreateSchema, productIdSchema, productSearchSchema, productUpdateSchema } from './service.js';

export function createMarketplaceRouter(service: MarketplaceService): Router {
  const router = Router();
  router.get('/products', validate('query', productSearchSchema), async (request, response) => sendSuccess(response, await service.search(request.query as never, request.auth?.userId)));
  router.get('/products/:id', validate('params', productIdSchema), async (request, response) => sendSuccess(response, await service.detail(param(request.params.id), request.auth?.userId)));
  router.post('/products', requireAuth, validate('body', productCreateSchema), async (request, response) => response.status(201).json({ success: true, data: await service.create(currentUserId(request), request.body), meta: {} }));
  router.patch('/products/:id', requireAuth, validate('params', productIdSchema), validate('body', productUpdateSchema), async (request, response) => sendSuccess(response, await service.update(param(request.params.id), currentUserId(request), request.body)));
  router.patch('/products/:id/inventory', requireAuth, validate('params', productIdSchema), validate('body', inventorySchema), async (request, response) => sendSuccess(response, await service.updateInventory(param(request.params.id), currentUserId(request), request.body.availableQuantity)));
  return router;
}

export function createCategoryRouter(service: MarketplaceService): Router {
  const router = Router();
  router.get('/', async (_request, response) => sendSuccess(response, await service.categories()));
  return router;
}

function param(value: string | string[] | undefined): string {
  return typeof value === 'string' ? value : '';
}
