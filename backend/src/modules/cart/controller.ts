import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import { CartService } from './service.js';

export function createCartController(service: CartService) {
  const get: RequestHandler = async (request, response) => sendSuccess(response, await service.get(currentUserId(request)));
  const addItem: RequestHandler = async (request, response) => sendSuccess(response, await service.addItem(currentUserId(request), request.body));
  const updateItem: RequestHandler = async (request, response) => sendSuccess(response, await service.updateItem(currentUserId(request), String(request.params.productId), request.body.quantity));
  const removeItem: RequestHandler = async (request, response) => sendSuccess(response, await service.removeItem(currentUserId(request), String(request.params.productId)));
  const clear: RequestHandler = async (request, response) => sendSuccess(response, await service.clear(currentUserId(request)));
  return { get, addItem, updateItem, removeItem, clear };
}
