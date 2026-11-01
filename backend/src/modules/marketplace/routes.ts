import { Router } from 'express';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { paginationQuerySchema, type Pagination } from '../../utils/pagination.js';
import { MarketplaceService, inventorySchema, productCreateSchema, productIdSchema, productSearchSchema, productUpdateSchema, marketplaceSearchSchema, sellerDeliverySettingsSchema, sellerStoreSchema, sellerStoreSlugSchema, sellerUsernameSchema } from './service.js';

export function createMarketplaceRouter(service: MarketplaceService): Router {
  const router = Router();
  router.get('/sellers/:username/store', validate('params', sellerUsernameSchema), async (request, response) => sendSuccess(response, await service.publicSellerStoreByUsername(param(request.params.username))));
  router.get('/sellers/:username/reviews', validate('params', sellerUsernameSchema), validate('query', paginationQuerySchema), async (request, response) => sendSuccess(response, await service.sellerReviews(param(request.params.username), request.query as never)));
  router.get('/products/:id/reviews', validate('params', productIdSchema), validate('query', paginationQuerySchema), async (request, response) => sendSuccess(response, await service.productReviews(param(request.params.id), request.query as never)));
  router.get('/sellers/:username/products', validate('params', sellerUsernameSchema), validate('query', productSearchSchema), async (request, response) => sendSuccess(response, await service.sellerProductsByUsername(param(request.params.username), request.query as never, request.auth?.userId)));
  router.get('/search', validate('query', marketplaceSearchSchema), async (request, response) => sendSuccess(response, await service.searchAll(String(request.query.q ?? ''), request.auth?.userId)));
  router.get('/products', validate('query', productSearchSchema), async (request, response) => sendSuccess(response, await service.search(request.query as never, request.auth?.userId)));
  router.get('/sellers/:id/delivery-settings', validate('params', productIdSchema), async (request, response) => sendSuccess(response, await service.sellerDeliverySettings(param(request.params.id))));
  router.get('/seller/store', requireAuth, async (request, response) => sendSuccess(response, await service.sellerStore(currentUserId(request))));
  router.put('/seller/store', requireAuth, validate('body', sellerStoreSchema), async (request, response) => sendSuccess(response, await service.updateSellerStore(currentUserId(request), request.body)));
  router.get('/stores/:slug', validate('params', sellerStoreSlugSchema), async (request, response) => sendSuccess(response, await service.publicSellerStore(param(request.params.slug))));
  router.get('/seller/delivery-settings', requireAuth, async (request, response) => sendSuccess(response, await service.sellerDeliverySettings(currentUserId(request))));
  router.patch('/seller/delivery-settings', requireAuth, validate('body', sellerDeliverySettingsSchema), async (request, response) => sendSuccess(response, await service.updateSellerDeliverySettings(currentUserId(request), request.body)));
  router.get('/products/:id', validate('params', productIdSchema), async (request, response) => sendSuccess(response, await service.detail(param(request.params.id), request.auth?.userId)));
  router.post('/products', requireAuth, validate('body', productCreateSchema), async (request, response) => response.status(201).json({ success: true, data: await service.create(currentUserId(request), request.body), meta: {} }));
  router.patch('/products/:id', requireAuth, validate('params', productIdSchema), validate('body', productUpdateSchema), async (request, response) => sendSuccess(response, await service.update(param(request.params.id), currentUserId(request), request.body)));
  router.patch('/products/:id/inventory', requireAuth, validate('params', productIdSchema), validate('body', inventorySchema), async (request, response) => sendSuccess(response, await service.updateInventory(param(request.params.id), currentUserId(request), request.body.availableQuantity)));
  return router;
}

export function createCategoryRouter(service: MarketplaceService): Router {
  const router = Router();
  router.get('/', validate('query', paginationQuerySchema), async (request, response) => {
    const query = request.query as unknown as Pagination;
    return sendSuccess(response, await service.categories(query.page, query.limit));
  });
  return router;
}

function param(value: string | string[] | undefined): string {
  return typeof value === 'string' ? value : '';
}
