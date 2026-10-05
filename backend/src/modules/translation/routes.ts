import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { createTranslationController } from './controller.js';
import { translationRequestIdSchema, translateSchema } from './schemas.js';
import { TranslationService } from './service.js';

export function createTranslationRouter(service: TranslationService): Router {
  const router = Router();
  const controller = createTranslationController(service);
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.post('/', createRateLimiter({ name: 'translation', windowMs: 60_000, max: 10 }), validate('body', translateSchema), controller.translate);
  router.get('/requests/:requestId', validate('params', translationRequestIdSchema), controller.getRequest);
  return router;
}
