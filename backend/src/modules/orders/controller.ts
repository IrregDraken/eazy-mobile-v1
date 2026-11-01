import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { idempotencyKey } from '../../middleware/idempotency.js';
import { sendSuccess } from '../../utils/http.js';
import { OrderService } from './service.js';

export function createOrderController(service: OrderService) {
  const create: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.create(currentUserId(request), idempotencyKey(request), request.body.fulfillments), meta: {} });
  const list: RequestHandler = async (request, response) => sendSuccess(response, await service.list(currentUserId(request), request.query as never));
  const addresses: RequestHandler = async (request, response) => sendSuccess(response, await service.addresses(currentUserId(request)));
  const createAddress: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.createAddress(currentUserId(request), request.body), meta: {} });
  const updateAddress: RequestHandler = async (request, response) => sendSuccess(response, await service.updateAddress(currentUserId(request), String(request.params.id), request.body));
  const deleteAddress: RequestHandler = async (request, response) => sendSuccess(response, await service.deleteAddress(currentUserId(request), String(request.params.id)));
  const get: RequestHandler = async (request, response) => sendSuccess(response, await service.get(currentUserId(request), String(request.params.id)));
  return { create, list, get, addresses, createAddress, updateAddress, deleteAddress };
}
