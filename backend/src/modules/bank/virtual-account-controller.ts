import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import type { VirtualAccountService } from './virtual-account-service.js';

export function createVirtualAccountController(service: VirtualAccountService) {
  const capabilities: RequestHandler = async (_request, response) => sendSuccess(response, service.capabilities());
  const get: RequestHandler = async (request, response) => sendSuccess(response, await service.get(currentUserId(request)));
  const assign: RequestHandler = async (request, response) => sendSuccess(response, await service.assign(currentUserId(request), request.body.consent));
  return { capabilities, get, assign };
}