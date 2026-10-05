import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import type { Logger } from 'pino';
import type { AppConfig } from './config/env.js';
import { errorHandler, notFoundHandler, AppError } from './middleware/errors.js';
import { requestId } from './middleware/request-id.js';
import { enforceHttps } from './middleware/security.js';
import { createRateLimiter } from './middleware/rate-limit.js';
import { sendSuccess } from './utils/http.js';
import type { RequestHandler, Router } from 'express';

export interface AppOptions {
  authMiddleware?: RequestHandler;
  authRouter?: Router;
  emailVerificationRouter?: Router;
  profileRouter?: Router;
  socialRouter?: Router;
  postRouter?: Router;
  homeRouter?: Router;
  engagementRouter?: Router;
  marketplaceRouter?: Router;
  marketplaceCategoryRouter?: Router;
  discoverRouter?: Router;
  cartRouter?: Router;
  orderRouter?: Router;
  chatRouter?: Router;
  translationRouter?: Router;
  locationRouter?: Router;
  walletRouter?: Router;
  bankRouter?: Router;
  bankTransferRouter?: Router;
  virtualAccountRouter?: Router;
  qrRouter?: Router;
  paymentRouter?: Router;
  notificationRouter?: Router;
  deepLinkRouter?: Router;
  assistRouter?: Router;
  settingsRouter?: Router;
  blockRouter?: Router;
  mediaRouter?: Router;
  readinessCheck?: () => Promise<boolean>;
}

export function createApp(config: AppConfig, logger: Logger, options: AppOptions = {}) {
  const app = express();
  app.disable('x-powered-by');
  if (config.TRUST_PROXY) app.set('trust proxy', true);
  app.use(helmet());
  const corsOrigins = config.CORS_ORIGIN.split(',').map(origin => origin.trim()).filter(Boolean);
  app.use(cors({ origin: config.CORS_ORIGIN === '*' ? true : (origin, callback) => {
    if (!origin || corsOrigins.includes(origin)) return callback(null, true);
    return callback(new Error('CORS origin not allowed'));
  }}));
  app.use(express.json({ limit: '1mb', verify: (request, _response, buffer) => { (request as import('express').Request).rawBody = buffer.toString('utf8'); } }));
  app.use(requestId);
  app.use((request, response, next) => {
    const startedAt = Date.now();
    logger.info({ event: 'request.started', requestId: request.id, method: request.method, path: request.path }, 'request started');
    response.on('finish', () => logger.info({
      event: 'request.completed', requestId: request.id, route: request.route?.path ?? request.path,
      method: request.method, statusCode: response.statusCode, durationMs: Date.now() - startedAt,
      authenticated: Boolean(request.auth), userId: request.auth?.userId
    }, 'request completed'));
    next();
  });
  app.get('/health', (_request, response) => sendSuccess(response, { status: 'ok', service: 'eazy-backend', version: '0.1.0' }));
  app.get('/ready', async (_request, response) => {
    try {
      const ready = options.readinessCheck ? await options.readinessCheck() : true;
      if (!ready) return response.status(503).json({ success: false, error: { code: 'SERVICE_UNAVAILABLE', message: 'Service is not ready', details: {} } });
      return sendSuccess(response, { status: 'ready', service: 'eazy-backend' });
    } catch (error) {
      logger.warn({ event: 'readiness.failed', error: error instanceof Error ? error.message : 'unknown' }, 'readiness check failed');
      return response.status(503).json({ success: false, error: { code: 'SERVICE_UNAVAILABLE', message: 'Service is not ready', details: {} } });
    }
  });

  if (config.ENFORCE_HTTPS) app.use(enforceHttps);
  app.use(createRateLimiter({ name: 'public', windowMs: config.RATE_LIMIT_WINDOW_MS, max: config.RATE_LIMIT_MAX }));
  if (options.authMiddleware) app.use(options.authMiddleware);

  app.get('/v1', (_request, response) => sendSuccess(response, { version: 'v1', status: 'available' }));

  if (options.emailVerificationRouter) app.use('/v1/auth', options.emailVerificationRouter);
  if (options.authMiddleware && options.authRouter) app.use('/v1/auth', options.authRouter);
  else app.use('/v1/auth', (_request, _response, next) => next(new AppError('SERVICE_UNAVAILABLE', 'Authentication is not configured')));
  if (options.profileRouter) app.use('/v1/profiles', options.profileRouter);
  if (options.socialRouter) app.use('/v1/social', options.socialRouter);
  if (options.postRouter) app.use('/v1/posts', options.postRouter);
  if (options.homeRouter) app.use('/v1/home', options.homeRouter);
  if (options.engagementRouter) app.use('/v1', options.engagementRouter);
  if (options.marketplaceRouter) app.use('/v1/marketplace', options.marketplaceRouter);
  if (options.marketplaceCategoryRouter) app.use('/v1/marketplace/categories', options.marketplaceCategoryRouter);
  if (options.discoverRouter) app.use('/v1/discover', options.discoverRouter);
  if (options.cartRouter) app.use('/v1/cart', options.cartRouter);
  if (options.orderRouter) app.use('/v1/orders', options.orderRouter);
  if (options.chatRouter) app.use('/v1/chat', options.chatRouter);
  if (options.translationRouter) app.use('/v1/translation', options.translationRouter);
  if (options.locationRouter) app.use('/v1/location', options.locationRouter);
  if (options.walletRouter) app.use('/v1/wallet', options.walletRouter);
  if (options.bankRouter) app.use('/v1/banks', options.bankRouter);
  if (options.bankTransferRouter) app.use('/v1/bank-transfers', options.bankTransferRouter);
  if (options.virtualAccountRouter) app.use('/v1/wallet/virtual-account', options.virtualAccountRouter);
  if (options.qrRouter) app.use('/v1/wallet/qr', options.qrRouter);
  if (options.paymentRouter) app.use('/v1/payments', options.paymentRouter);
  if (options.notificationRouter) app.use('/v1/notifications', options.notificationRouter);
  if (options.deepLinkRouter) app.use('/v1/deep-links', options.deepLinkRouter);
  if (options.assistRouter) app.use('/v1/assist', options.assistRouter);
  if (options.settingsRouter) app.use('/v1/settings', options.settingsRouter);
  if (options.blockRouter) app.use('/v1/blocks', options.blockRouter);
  if (options.mediaRouter) app.use('/v1/media', options.mediaRouter);

  app.use(notFoundHandler);
  app.use(errorHandler(logger));
  return app;
}
