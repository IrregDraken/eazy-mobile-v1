import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { createMediaController } from './controller.js';
import { mediaPathSchema, mediaUploadSchema } from './schemas.js';
import type { MediaService } from './service.js';
export function createMediaRouter(service: MediaService): Router {
  const router = Router(); const controller = createMediaController(service);
  const uploadLimit = createRateLimiter({ name: 'media-upload-url', windowMs: 60_000, max: 20 });
  const signedUrlLimit = createRateLimiter({ name: 'media-signed-url', windowMs: 60_000, max: 60 });
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.post('/upload-url', uploadLimit, validate('body', mediaUploadSchema), controller.upload);
  router.post('/signed-url', signedUrlLimit, validate('body', mediaPathSchema), controller.sign);
  router.post('/signed-message-attachment-url', uploadLimit, validate('body', mediaPathSchema), controller.signMessageAttachment);
  return router;
}