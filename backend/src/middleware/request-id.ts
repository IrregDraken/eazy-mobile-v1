import type { RequestHandler } from 'express';
import { randomUUID } from 'node:crypto';

const requestIdPattern = /^[A-Za-z0-9._:-]{1,128}$/;

export function normalizeRequestId(value: string | undefined): string {
  return value && requestIdPattern.test(value) ? value : randomUUID();
}

export const requestId: RequestHandler = (request, response, next) => {
  const id = normalizeRequestId(request.header('x-request-id'));
  request.id = id;
  response.setHeader('x-request-id', id);
  next();
};
