import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { AssistService } from './service.js';
import { assistHistoryQuerySchema, assistSessionParamsSchema, createSessionSchema, assistMessageSchema } from './schemas.js';
import { createAssistController } from './controller.js';

export function createAssistRouter(service: AssistService): Router {
  const router = Router();
  const controller = createAssistController(service);
  const sessionLimit = createRateLimiter({ name: 'assist-session', windowMs: 60_000, max: 10 });
  const messageLimit = createRateLimiter({ name: 'assist-message', windowMs: 60_000, max: 10 });
  router.use(requireAuth);
  router.get('/capabilities', controller.capabilities);
  router.post('/sessions', sessionLimit, validate('body', createSessionSchema), controller.createSession);
  router.get('/sessions', validate('query', assistHistoryQuerySchema), controller.listSessions);
  router.get('/sessions/:id', validate('params', assistSessionParamsSchema), controller.getSession);
  router.delete('/sessions/:id', sessionLimit, validate('params', assistSessionParamsSchema), controller.closeSession);
  router.get('/sessions/:id/messages', validate('params', assistSessionParamsSchema), validate('query', assistHistoryQuerySchema), controller.listMessages);
  router.post('/sessions/:id/messages', messageLimit, validate('params', assistSessionParamsSchema), validate('body', assistMessageSchema), controller.sendMessage);
  return router;
}
