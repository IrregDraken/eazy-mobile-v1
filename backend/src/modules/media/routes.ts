import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { createMediaController } from './controller.js';
import { mediaPathSchema, mediaUploadSchema } from './schemas.js';
import type { MediaService } from './service.js';
export function createMediaRouter(service: MediaService): Router {
  const router = Router(); const controller = createMediaController(service);
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.post('/upload-url', validate('body', mediaUploadSchema), controller.upload);
  router.post('/signed-url', validate('body', mediaPathSchema), controller.sign);
  return router;
}