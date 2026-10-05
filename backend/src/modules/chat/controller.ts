import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import { ChatService } from './service.js';

export function createChatController(service: ChatService) {
  const createConversation: RequestHandler = async (request, response) => {
    const result = await service.createConversation(currentUserId(request), request.body.username);
    return response.status(result.created ? 201 : 200).json({ success: true, data: { conversation: result.conversation }, meta: {} });
  };
  const listConversations: RequestHandler = async (request, response) => sendSuccess(response, await service.listConversations(currentUserId(request), request.query as never));
  const getConversation: RequestHandler = async (request, response) => sendSuccess(response, await service.getConversation(currentUserId(request), String(request.params.conversationId)));
  const listMessages: RequestHandler = async (request, response) => sendSuccess(response, await service.listMessages(currentUserId(request), String(request.params.conversationId), request.query as never));
  const sendMessage: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.sendMessage(currentUserId(request), String(request.params.conversationId), request.body), meta: {} });
  const deleteMessage: RequestHandler = async (request, response) => sendSuccess(response, await service.deleteMessage(currentUserId(request), String(request.params.messageId)));
  const editMessage: RequestHandler = async (request, response) => sendSuccess(response, await service.editMessage(currentUserId(request), String(request.params.messageId), request.body.body));
  const reportMessage: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.reportMessage(currentUserId(request), String(request.params.messageId), request.body.reason), meta: {} });
  const addReaction: RequestHandler = async (request, response) => sendSuccess(response, await service.addReaction(currentUserId(request), String(request.params.messageId), request.body.reaction));
  const removeReaction: RequestHandler = async (request, response) => sendSuccess(response, await service.removeReaction(currentUserId(request), String(request.params.messageId), String(request.params.reaction)));
  const markRead: RequestHandler = async (request, response) => sendSuccess(response, await service.markRead(currentUserId(request), String(request.params.conversationId), request.body.lastReadMessageId));
  return { createConversation, listConversations, getConversation, listMessages, sendMessage, deleteMessage, editMessage, reportMessage, addReaction, removeReaction, markRead };
}
