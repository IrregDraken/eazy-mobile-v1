import { Router } from 'express';
import { z } from 'zod';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { paginationQuerySchema } from '../../utils/pagination.js';
import { createPostSchema, postIdSchema, PostService } from './service.js';

export function createPostRouter(service: PostService): Router {
  const router = Router();
  router.post('/', requireAuth, validate('body', createPostSchema), async (request, response) => {
    const post = await service.create(currentUserId(request), request.body);
    return response.status(201).json({ success: true, data: { post }, meta: {} });
  });
  router.get('/mine', requireAuth, validate('query', paginationQuerySchema), async (request, response) => sendSuccess(response, await service.mine(currentUserId(request), request.query as never)));
  router.get('/:id', validate('params', postIdSchema), async (request, response) => sendSuccess(response, { post: await service.getById(param(request.params.id), request.auth?.userId) }));
  router.delete('/:id', requireAuth, validate('params', postIdSchema), async (request, response) => sendSuccess(response, await service.delete(param(request.params.id), currentUserId(request))));
  return router;
}

const feedQuerySchema = paginationQuerySchema.extend({
  mode: z.enum(['for_you', 'following', 'trending']).default('for_you')
});

export function createHomeRouter(service: PostService): Router {
  const router = Router();
  router.get('/feed', requireAuth, validate('query', feedQuerySchema), async (request, response) => sendSuccess(response, await service.feed(currentUserId(request), request.query as never)));
  return router;
}

function param(value: string | string[] | undefined): string {
  return typeof value === 'string' ? value : '';
}
