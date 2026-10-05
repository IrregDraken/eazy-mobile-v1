import { Router } from 'express';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { paginationQuerySchema } from '../../utils/pagination.js';
import { commentIdParamSchema, commentSchema, EngagementService, postIdParamSchema } from './service.js';

export function createEngagementRouter(service: EngagementService): Router {
  const router = Router();

  router.post('/posts/:postId/like', requireAuth, validate('params', postIdParamSchema), async (request, response) => sendSuccess(response, await service.like(param(request.params.postId), currentUserId(request))));
  router.delete('/posts/:postId/like', requireAuth, validate('params', postIdParamSchema), async (request, response) => sendSuccess(response, await service.unlike(param(request.params.postId), currentUserId(request))));

  router.post('/posts/:postId/comments', requireAuth, validate('params', postIdParamSchema), validate('body', commentSchema), async (request, response) => sendSuccess(response, await service.createComment(param(request.params.postId), currentUserId(request), request.body.content)));
  router.get('/posts/:postId/comments', requireAuth, validate('params', postIdParamSchema), validate('query', paginationQuerySchema), async (request, response) => sendSuccess(response, await service.listComments(param(request.params.postId), currentUserId(request), request.query as never)));
  router.delete('/comments/:commentId', requireAuth, validate('params', commentIdParamSchema), async (request, response) => sendSuccess(response, await service.deleteComment(param(request.params.commentId), currentUserId(request))));

  router.post('/posts/:postId/save', requireAuth, validate('params', postIdParamSchema), async (request, response) => sendSuccess(response, await service.save(param(request.params.postId), currentUserId(request))));
  router.delete('/posts/:postId/save', requireAuth, validate('params', postIdParamSchema), async (request, response) => sendSuccess(response, await service.unsave(param(request.params.postId), currentUserId(request))));
  router.get('/profiles/me/saved-posts', requireAuth, validate('query', paginationQuerySchema), async (request, response) => sendSuccess(response, await service.savedPosts(currentUserId(request), request.query as never)));

  return router;
}

function param(value: string | string[] | undefined): string {
  return typeof value === 'string' ? value : '';
}
