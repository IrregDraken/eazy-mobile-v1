import type { RequestHandler } from 'express';
import { sendSuccess } from '../../utils/http.js';
import type { BankService } from './service.js';
export function createBankController(service: BankService) {
  const capabilities: RequestHandler = async (_request, response) => sendSuccess(response, service.capabilities());
  const listBanks: RequestHandler = async (request, response) => sendSuccess(response, await service.listBanks(String((request.query as { currency: string }).currency)));
  const resolveAccount: RequestHandler = async (request, response) => sendSuccess(response, await service.resolveAccount(request.body));
  return { capabilities, listBanks, resolveAccount };
}
