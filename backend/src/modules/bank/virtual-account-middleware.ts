import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { AppError } from '../../middleware/errors.js';
import type { VirtualAccountService } from './virtual-account-service.js';

export function requireActiveVirtualAccount(
  service?: VirtualAccountService,
): RequestHandler {
  return async (request, _response, next) => {
    if (!service) {
      next(
        new AppError(
          'SERVICE_UNAVAILABLE',
          'Wallet activation checks are unavailable.',
        ),
      );
      return;
    }
    try {
      await service.assertActive(currentUserId(request));
      next();
    } catch (error) {
      next(error);
    }
  };
}
