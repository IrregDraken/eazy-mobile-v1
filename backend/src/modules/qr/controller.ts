import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { idempotencyKey } from '../../middleware/idempotency.js';
import { sendSuccess } from '../../utils/http.js';
import type { WalletService } from '../wallet/service.js';
import type { QrService } from './service.js';

export function createQrController(qrService: QrService, walletService: WalletService) {
  const create: RequestHandler = async (request, response) => sendSuccess(response, await qrService.create(currentUserId(request), (request.body as { expiresInDays: number }).expiresInDays));
  const resolve: RequestHandler = async (request, response) => sendSuccess(response, await qrService.resolve((request.body as { token: string }).token));
  const revoke: RequestHandler = async (request, response) => sendSuccess(response, await qrService.revoke(currentUserId(request), (request.params as { id: string }).id));
  const pay: RequestHandler = async (request, response) => {
    const body = request.body as { token: string; amount: string; currency: string };
    const token = body.token;
    const result = await walletService.payQr(currentUserId(request), (client, allowInactive) => qrService.resolveForPayment(client, token, allowInactive), body.amount, body.currency, idempotencyKey(request));
    return sendSuccess(response, result);
  };
  return { create, resolve, revoke, pay };
}
