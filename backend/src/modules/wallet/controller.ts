import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { idempotencyKey } from '../../middleware/idempotency.js';
import { sendSuccess } from '../../utils/http.js';
import type { WalletService } from './service.js';

export function createWalletController(service: WalletService): {
  getWallet: RequestHandler;
  createWallet: RequestHandler;
  listTransactions: RequestHandler;
  getTransaction: RequestHandler;
  transfer: RequestHandler;
} {
  const getWallet: RequestHandler = async (request, response) => sendSuccess(response, await service.getWallets(currentUserId(request)));
  const createWallet: RequestHandler = async (request, response) => {
    const input = request.body as { currency: string };
    return sendSuccess(response, await service.createWallet(currentUserId(request), input.currency));
  };
  const listTransactions: RequestHandler = async (request, response) => {
    const pagination = request.query as unknown as { page: number; limit: number };
    return sendSuccess(response, await service.listTransactions(currentUserId(request), pagination));
  };
  const getTransaction: RequestHandler = async (request, response) => {
    const params = request.params as { id: string };
    return sendSuccess(response, await service.getTransaction(currentUserId(request), params.id));
  };
  const transfer: RequestHandler = async (request, response) => {
    const body = request.body as { recipientUsername: string; amount: string; currency: string };
    const transaction = await service.transfer(currentUserId(request), body, idempotencyKey(request));
    return sendSuccess(response, transaction);
  };
  return { getWallet, createWallet, listTransactions, getTransaction, transfer };
}
