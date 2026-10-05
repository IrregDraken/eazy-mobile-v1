import { Router } from 'express';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { DiscoverService, discoverQuerySchema } from './service.js';
import { productSearchSchema } from '../marketplace/service.js';
import { paginationQuerySchema } from '../../utils/pagination.js';

export function createDiscoverRouter(service: DiscoverService): Router {
  const router = Router();
  router.get('/', validate('query', discoverQuerySchema), async (request, response) => sendSuccess(response, await service.unified(request.query as never, request.auth?.userId)));
  router.get('/products', validate('query', productSearchSchema), async (request, response) => sendSuccess(response, await service.products(request.query as never, request.auth?.userId)));
  router.get('/categories', validate('query', paginationQuerySchema), async (request, response) => sendSuccess(response, await service.unified({ type: 'categories', ...request.query } as never)));
  return router;
}
