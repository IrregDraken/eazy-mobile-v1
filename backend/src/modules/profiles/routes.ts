import { Router } from 'express';
import { z } from 'zod';
import { requireAuth, currentUserId } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { ProfileService, profilePatchSchema, usernameSchema } from './service.js';

export function createProfileRouter(service: ProfileService): Router {
  const router = Router();
  router.get('/me', requireAuth, async (request, response) => sendSuccess(response, { profile: await service.getMe(currentUserId(request)) }));
  router.patch('/me', requireAuth, validate('body', profilePatchSchema), async (request, response) => sendSuccess(response, { profile: await service.update(currentUserId(request), request.body) }));
  router.get('/me/stats', requireAuth, async (request, response) => sendSuccess(response, { stats: await service.getStats(currentUserId(request)) }));
  router.post('/me/onboarding/complete', requireAuth, async (request, response) => sendSuccess(response, { profile: await service.completeOnboarding(currentUserId(request)) }));
  router.get('/username/:username/availability', validate('params', z.object({ username: usernameSchema })), async (request, response) => {
    const currentUser = request.auth?.userId;
    return sendSuccess(response, await service.isUsernameAvailable(param(request.params.username), currentUser));
  });
  router.get('/:username', validate('params', z.object({ username: usernameSchema })), async (request, response) => sendSuccess(response, { profile: await service.getPublic(param(request.params.username), request.auth?.userId) }));
  return router;
}

function param(value: string | string[] | undefined): string {
  return typeof value === 'string' ? value : '';
}
