import type { RequestHandler } from 'express';
import { AppError } from './errors.js';

export const enforceHttps: RequestHandler = (request, _response, next) => {
  const forwardedProto = request.header('x-forwarded-proto');
  if (request.secure || forwardedProto === 'https') return next();
  next(new AppError('BAD_REQUEST', 'HTTPS is required'));
};
