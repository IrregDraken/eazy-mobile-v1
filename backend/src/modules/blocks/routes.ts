import { Router } from 'express';
import { z } from 'zod';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { paginationQuerySchema } from '../../utils/pagination.js';
import { sendSuccess } from '../../utils/http.js';
import type { SocialService } from '../social/service.js';

const createBlockSchema = z.object({ userId: z.string().uuid() }).strict();
const blockParamsSchema = z.object({ userId: z.string().uuid() }).strict();

export function createBlockRouter(service: SocialService): Router {
  const router = Router();
  const mutationLimit = createRateLimiter({ name: 'block-mutation', windowMs: 60_000, max: 20 });
  router.get('/', requireAuth, validate('query', paginationQuerySchema), async (request, response) =>
    sendSuccess(response, await service.listBlocks(currentUserId(request), request.query as never)));
  router.post('/', requireAuth, mutationLimit, validate('body', createBlockSchema), async (request, response) =>
    sendSuccess(response, await service.blockUser(currentUserId(request), (request.body as z.infer<typeof createBlockSchema>).userId)));
  router.delete('/:userId', requireAuth, mutationLimit, validate('params', blockParamsSchema), async (request, response) =>
    sendSuccess(response, await service.unblockUser(currentUserId(request), (request.params as z.infer<typeof blockParamsSchema>).userId)));
  return router;
}
