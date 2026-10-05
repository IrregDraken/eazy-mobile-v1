import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { DeepLinkService } from './service.js';

export const resolveDeepLinkQuerySchema = z.object({ path: z.string().min(1).max(2048) }).strict();

export function createDeepLinkRouter(service: DeepLinkService): Router {
  const router = Router();
  router.get('/resolve', validate('query', resolveDeepLinkQuerySchema), async (request, response) => {
    const { path } = request.query as { path: string };
    const target = await service.resolve(path, request.auth?.userId);
    return sendSuccess(response, target);
  });
  return router;
}
