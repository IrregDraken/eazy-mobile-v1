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
  const createReview: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.createReview(currentUserId(request), String(request.params.id), String(request.params.itemId), request.body.rating, request.body.reviewText), meta: {} });
  const sellerPayables: RequestHandler = async (request, response) => sendSuccess(response, await service.sellerPayables(currentUserId(request), request.query as never));
  const sellerOrders: RequestHandler = async (request, response) => sendSuccess(response, await service.sellerOrders(currentUserId(request), request.query as never));
  const updateSellerFulfillment: RequestHandler = async (request, response) => sendSuccess(response, await service.updateSellerFulfillment(currentUserId(request), String(request.params.id), String(request.params.fulfillmentId), request.body));
  const confirmReceived: RequestHandler = async (request, response) => sendSuccess(response, await service.confirmReceived(currentUserId(request), String(request.params.id), String(request.params.fulfillmentId)));
  const createDispute: RequestHandler = async (request, response) => response.status(201).json({ success: true, data: await service.createDispute(currentUserId(request), String(request.params.id), String(request.params.fulfillmentId), request.body), meta: {} });
  const get: RequestHandler = async (request, response) => sendSuccess(response, await service.get(currentUserId(request), String(request.params.id)));
  return { create, list, get, addresses, createAddress, updateAddress, deleteAddress, sellerOrders, sellerPayables, updateSellerFulfillment, confirmReceived, createDispute, createReview };
}
