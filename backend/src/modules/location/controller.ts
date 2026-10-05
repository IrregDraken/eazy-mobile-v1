import type { RequestHandler } from 'express';
import { sendSuccess } from '../../utils/http.js';
import { LocationService } from './service.js';

export function createLocationController(service: LocationService) {
  const capabilities: RequestHandler = (_request, response) => sendSuccess(response, service.capabilities());
  const reverseGeocode: RequestHandler = async (request, response) => sendSuccess(response, await service.reverseGeocode(request.body));
  const search: RequestHandler = async (request, response) => {
    const query = request.query as unknown as { q: string; limit: number };
    return sendSuccess(response, await service.search({ query: query.q, limit: query.limit }));
  };
  return { capabilities, reverseGeocode, search };
}
