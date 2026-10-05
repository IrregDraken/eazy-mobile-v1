import { Router } from 'express';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { settingsPatchSchema } from './schemas.js';
import type { SettingsService } from './service.js';

export function createSettingsRouter(service: SettingsService): Router {
  const router = Router();
  const readLimit = createRateLimiter({ name: 'settings-read', windowMs: 60_000, max: 60 });
  const updateLimit = createRateLimiter({ name: 'settings-update', windowMs: 60_000, max: 20 });
  router.get('/', requireAuth, readLimit, async (request, response) => sendSuccess(response, await service.get(currentUserId(request))));
  router.patch('/', requireAuth, updateLimit, validate('body', settingsPatchSchema), async (request, response) => sendSuccess(response, await service.update(currentUserId(request), request.body)));
  return router;
}
