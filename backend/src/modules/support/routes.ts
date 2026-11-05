import { Router } from 'express';
import { z } from 'zod';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { createRateLimiter } from '../../middleware/rate-limit.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import type { SupportService } from './service.js';

const reportLimit = createRateLimiter({ name: 'support-report-create', windowMs: 60 * 60_000, max: 5 });
const reportSchema = z.object({
  category: z.enum(['bug', 'account', 'payments', 'other']),
  subject: z.string().trim().min(5).max(120),
  description: z.string().trim().min(20).max(2000),
}).strict();

export function createSupportRouter(service: SupportService) {
  const router = Router();

  router.get('/config', requireAuth, (_request, response) => {
    sendSuccess(response, service.getConfig());
  });

  router.post('/reports', requireAuth, reportLimit, validate('body', reportSchema), async (request, response, next) => {
    try {
      sendSuccess(response, await service.createReport(currentUserId(request), request.body));
    } catch (error) {
      next(error);
    }
  });

  return router;
}
