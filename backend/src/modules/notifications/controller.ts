import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import { NotificationService } from './service.js';

export function createNotificationController(service: NotificationService) {
  const list: RequestHandler = async (request, response) => sendSuccess(response, await service.list(currentUserId(request), request.query as never));
  const get: RequestHandler = async (request, response) => sendSuccess(response, await service.get(currentUserId(request), String(request.params.id)));
  const markRead: RequestHandler = async (request, response) => sendSuccess(response, await service.markRead(currentUserId(request), String(request.params.id)));
  const markAllRead: RequestHandler = async (request, response) => sendSuccess(response, await service.markAllRead(currentUserId(request)));
  const unreadCount: RequestHandler = async (request, response) => sendSuccess(response, await service.unreadCount(currentUserId(request)));
  const registerDevice: RequestHandler = async (request, response) => sendSuccess(response, await service.registerDevice(currentUserId(request), request.body));
  const deleteDevice: RequestHandler = async (request, response) => sendSuccess(response, await service.deleteDevice(currentUserId(request), String(request.params.id)));
  return { list, get, markRead, markAllRead, unreadCount, registerDevice, deleteDevice };
}
