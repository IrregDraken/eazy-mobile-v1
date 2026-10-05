import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { idempotencyKey } from '../../middleware/idempotency.js';
import { sendSuccess } from '../../utils/http.js';
import type { PaymentService } from './service.js';

export function createPaymentController(service: PaymentService) {
  const capabilities: RequestHandler = async (_request, response) => sendSuccess(response, service.capabilities());
  const initialize: RequestHandler = async (request, response) => {
    const result = await service.initialize(currentUserId(request), request.body, idempotencyKey(request));
    return sendSuccess(response, result);
  };
  const get: RequestHandler = async (request, response) => sendSuccess(response, await service.get(currentUserId(request), (request.params as { id: string }).id));
  const verify: RequestHandler = async (request, response) => sendSuccess(response, await service.verify(currentUserId(request), (request.params as { id: string }).id));
  return { capabilities, initialize, get, verify };
}
