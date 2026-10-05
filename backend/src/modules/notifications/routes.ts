import { Router } from 'express';
import { currentUserId, requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { sendSuccess } from '../../utils/http.js';
import { paginationQuerySchema } from '../../utils/pagination.js';
import { NotificationService } from './service.js';
import { deviceIdSchema, deviceRegistrationSchema, notificationIdSchema } from './schemas.js';
import { createNotificationController } from './controller.js';

export function createNotificationRouter(service: NotificationService): Router {
  const router = Router();
  const controller = createNotificationController(service);
  router.get('/', requireAuth, validate('query', paginationQuerySchema), controller.list);
  router.get('/unread-count', requireAuth, controller.unreadCount);
  router.post('/read-all', requireAuth, controller.markAllRead);
  router.get('/:id', requireAuth, validate('params', notificationIdSchema), controller.get);
  router.post('/:id/read', requireAuth, validate('params', notificationIdSchema), controller.markRead);
  router.post('/devices', requireAuth, validate('body', deviceRegistrationSchema), controller.registerDevice);
  router.delete('/devices/:id', requireAuth, validate('params', deviceIdSchema), controller.deleteDevice);
  return router;
}
