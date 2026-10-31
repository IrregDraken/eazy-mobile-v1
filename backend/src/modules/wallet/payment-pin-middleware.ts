import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { AppError } from '../../middleware/errors.js';
import type { PaymentPinService } from './payment-pin-service.js';

export function requirePaymentPin(service: PaymentPinService): RequestHandler {
  return async (request, _response, next) => {
    const pin = request.header('x-payment-pin');
    if (!pin) return next(new AppError('UNAUTHORIZED', 'Enter your 6-digit payment PIN to continue'));
    try {
      await service.verify(currentUserId(request), pin);
      next();
    } catch (error) {
      next(error);
    }
  };
}
