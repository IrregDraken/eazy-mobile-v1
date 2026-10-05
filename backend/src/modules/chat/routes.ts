import { Router } from 'express';
import { requireAuth } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { ChatService } from './service.js';
import { createChatController } from './controller.js';
import {
  addReactionSchema,
  chatPaginationSchema,
  conversationParamsSchema,
  createConversationSchema,
  createMessageSchema,
  editMessageSchema,
  messageParamsSchema,
  reportMessageSchema,
  reactionParamsSchema,
  readStateSchema
} from './schemas.js';

export function createChatRouter(service: ChatService): Router {
  const router = Router();
  const controller = createChatController(service);
  router.post('/conversations', requireAuth, validate('body', createConversationSchema), controller.createConversation);
  router.get('/conversations', requireAuth, validate('query', chatPaginationSchema), controller.listConversations);
  router.post('/conversations/:conversationId/messages', requireAuth, validate('params', conversationParamsSchema), validate('body', createMessageSchema), controller.sendMessage);
  router.get('/conversations/:conversationId/messages', requireAuth, validate('params', conversationParamsSchema), validate('query', chatPaginationSchema), controller.listMessages);
  router.post('/conversations/:conversationId/read', requireAuth, validate('params', conversationParamsSchema), validate('body', readStateSchema), controller.markRead);
  router.get('/conversations/:conversationId', requireAuth, validate('params', conversationParamsSchema), controller.getConversation);
  router.post('/messages/:messageId/reactions', requireAuth, validate('params', messageParamsSchema), validate('body', addReactionSchema), controller.addReaction);
  router.delete('/messages/:messageId/reactions/:reaction', requireAuth, validate('params', reactionParamsSchema), controller.removeReaction);
  router.delete('/messages/:messageId', requireAuth, validate('params', messageParamsSchema), controller.deleteMessage);
  router.patch('/messages/:messageId', requireAuth, validate('params', messageParamsSchema), validate('body', editMessageSchema), controller.editMessage);
  router.post('/messages/:messageId/report', requireAuth, validate('params', messageParamsSchema), validate('body', reportMessageSchema), controller.reportMessage);
  return router;
}
