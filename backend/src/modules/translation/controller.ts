import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import { TranslationService } from './service.js';

export function createTranslationController(service: TranslationService) {
  const capabilities: RequestHandler = (_request, response) => sendSuccess(response, service.capabilities());
  const translate: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.translate(currentUserId(request), request.body), meta: {} });
  const getRequest: RequestHandler = async (request, response) => sendSuccess(response, await service.getRequest(currentUserId(request), String(request.params.requestId)));
  return { capabilities, translate, getRequest };
}
