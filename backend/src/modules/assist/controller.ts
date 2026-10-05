import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import { AssistService } from './service.js';

export function createAssistController(service: AssistService) {
  const capabilities: RequestHandler = (_request, response) => sendSuccess(response, service.capabilities());
  const createSession: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.createSession(currentUserId(request)), meta: {} });
  const listSessions: RequestHandler = async (request, response) => sendSuccess(response, await service.listSessions(currentUserId(request), request.query as never));
  const getSession: RequestHandler = async (request, response) => sendSuccess(response, await service.getSession(currentUserId(request), String(request.params.id)));
  const closeSession: RequestHandler = async (request, response) => sendSuccess(response, await service.closeSession(currentUserId(request), String(request.params.id)));
  const listMessages: RequestHandler = async (request, response) => sendSuccess(response, await service.listMessages(currentUserId(request), String(request.params.id), request.query as never));
  const sendMessage: RequestHandler = async (request, response) => sendSuccess(response, await service.sendMessage(currentUserId(request), String(request.params.id), request.body));
  return { capabilities, createSession, listSessions, getSession, closeSession, listMessages, sendMessage };
}
