import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { idempotencyKey } from '../../middleware/idempotency.js';
import { sendSuccess } from '../../utils/http.js';
import type { BankTransferService } from './transfer-service.js';
import type { VirtualAccountService } from './virtual-account-service.js';

export function createBankTransferController(service: BankTransferService, virtualAccounts?: VirtualAccountService) {
  const capabilities: RequestHandler = async (_request, response) => sendSuccess(response, service.capabilities());
  const initiate: RequestHandler = async (request, response) =>
    sendSuccess(response, await service.initiate(currentUserId(request), request.body, idempotencyKey(request)));
  const get: RequestHandler = async (request, response) =>
    sendSuccess(response, await service.verify(currentUserId(request), (request.params as { id: string }).id));
  const webhook: RequestHandler = async (request, response) => {
    const event = request.body as {
      event?: string;
      data?: { reference?: string; amount?: number; currency?: string };
    };
    const reference = String(event.data?.reference ?? '').trim();
    const amount = Number(event.data?.amount);
    const currency = String(event.data?.currency ?? '').trim().toUpperCase();
    if (!event.event || !reference || !Number.isSafeInteger(amount) || amount <= 0 || !currency) {
      return response.status(202).json({ success: true, data: { accepted: true, handled: false }, meta: {} });
    }
    const virtualResult = virtualAccounts ? await virtualAccounts.handleWebhook(event.event, event.data ?? {}) : { handled: false };
    const transferResult = reference && Number.isSafeInteger(amount) && amount > 0 && currency
      ? await service.handleWebhook(event.event, reference, (amount / 100).toFixed(2), currency)
      : { handled: false };
    return sendSuccess(response, { handled: virtualResult.handled || transferResult.handled, virtualAccount: virtualResult, transfer: transferResult });
  };
  return { capabilities, initiate, get, webhook };
}