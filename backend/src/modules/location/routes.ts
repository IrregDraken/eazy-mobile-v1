import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { createLocationController } from './controller.js';
import { locationSearchSchema, reverseGeocodeSchema } from './schemas.js';
import { LocationService } from './service.js';

export function createLocationRouter(service: LocationService): Router {
  const router = Router();
  const controller = createLocationController(service);
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.post('/reverse-geocode', createRateLimiter({ name: 'location-reverse', windowMs: 60_000, max: 20 }), validate('body', reverseGeocodeSchema), controller.reverseGeocode);
  router.get('/search', createRateLimiter({ name: 'location-search', windowMs: 60_000, max: 20 }), validate('query', locationSearchSchema), controller.search);
  return router;
}
