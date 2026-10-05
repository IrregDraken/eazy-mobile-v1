import type { RequestHandler } from 'express';
import { currentUserId } from '../../middleware/auth.js';
import { sendSuccess } from '../../utils/http.js';
import type { MediaService } from './service.js';
export function createMediaController(service: MediaService) {
  return {
    capabilities: (async (_req, res) => sendSuccess(res, service.capabilities())) as RequestHandler,
    upload: (async (req, res) => sendSuccess(res, await service.createUpload(currentUserId(req), req.body))) as RequestHandler,
    sign: (async (req, res) => sendSuccess(res, await service.signRead(currentUserId(req), req.body.path))) as RequestHandler
  };
}