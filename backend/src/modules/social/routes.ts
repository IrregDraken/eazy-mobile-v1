import { Router } from 'express';
import { requireAuth, currentUserId } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { reportSchema, searchQuerySchema, socialPaginationSchema, socialUsernameSchema, SocialService } from './service.js';
import { z } from 'zod';

export function createSocialRouter(service: SocialService): Router {
  const router = Router();
  const usernameParams = z.object({ username: socialUsernameSchema });

  router.post('/follow/:username', requireAuth, validate('params', usernameParams), async (request, response) => sendSuccess(response, await service.follow(currentUserId(request), param(request.params.username))));
  router.delete('/follow/:username', requireAuth, validate('params', usernameParams), async (request, response) => sendSuccess(response, await service.unfollow(currentUserId(request), param(request.params.username))));
  router.get('/followers/:username', validate('params', usernameParams), validate('query', socialPaginationSchema), async (request, response) => sendSuccess(response, await service.list(request.auth?.userId, 'followers', param(request.params.username), request.query as never)));
  router.get('/following/:username', validate('params', usernameParams), validate('query', socialPaginationSchema), async (request, response) => sendSuccess(response, await service.list(request.auth?.userId, 'following', param(request.params.username), request.query as never)));
  router.get('/relationship/:username', requireAuth, validate('params', usernameParams), async (request, response) => sendSuccess(response, await service.relationship(currentUserId(request), param(request.params.username))));

  router.post('/block/:username', requireAuth, validate('params', usernameParams), async (request, response) => sendSuccess(response, await service.block(currentUserId(request), param(request.params.username))));
  router.delete('/block/:username', requireAuth, validate('params', usernameParams), async (request, response) => sendSuccess(response, await service.unblock(currentUserId(request), param(request.params.username))));
  router.get('/blocks', requireAuth, validate('query', socialPaginationSchema), async (request, response) => sendSuccess(response, await service.listBlocks(currentUserId(request), request.query as never)));

  router.get('/users/search', requireAuth, validate('query', searchQuerySchema), async (request, response) => sendSuccess(response, await service.search(currentUserId(request), request.query as never)));
  router.post('/report/:username', requireAuth, validate('params', usernameParams), validate('body', reportSchema), async (request, response) => sendSuccess(response, await service.report(currentUserId(request), param(request.params.username), request.body.reason)));
  return router;
}

function param(value: string | string[] | undefined): string {
  return typeof value === 'string' ? value : '';
}
