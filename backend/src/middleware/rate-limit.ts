import type { RequestHandler } from 'express';
import { AppError } from './errors.js';

export interface RateLimitPolicy { windowMs: number; max: number; name: string; }

export class FixedWindowRateLimiter {
  private readonly buckets = new Map<string, { startedAt: number; count: number }>();

  consume(key: string, max: number, windowMs: number, now = Date.now()) {
    const bucket = this.buckets.get(key);
    if (!bucket || now - bucket.startedAt >= windowMs) {
      this.buckets.set(key, { startedAt: now, count: 1 });
      this.prune(now, windowMs);
      return { allowed: true, remaining: Math.max(0, max - 1), retryAfterMs: windowMs };
    }
    bucket.count += 1;
    return {
      allowed: bucket.count <= max,
      remaining: Math.max(0, max - bucket.count),
      retryAfterMs: Math.max(0, windowMs - (now - bucket.startedAt))
    };
  }

  private prune(now: number, windowMs: number) {
    if (this.buckets.size < 10_000) return;
    for (const [key, bucket] of this.buckets) if (now - bucket.startedAt >= windowMs) this.buckets.delete(key);
  }
}

export function createRateLimiter(policy: RateLimitPolicy): RequestHandler {
  const limiter = new FixedWindowRateLimiter();
  return (request, response, next) => {
    const key = `${policy.name}:${request.ip}`;
    const result = limiter.consume(key, policy.max, policy.windowMs);
    response.setHeader('x-rate-limit-limit', policy.max);
    response.setHeader('x-rate-limit-remaining', result.remaining);
    if (!result.allowed) {
      response.setHeader('retry-after', Math.ceil(result.retryAfterMs / 1000));
      return next(new AppError('RATE_LIMITED', 'Too many requests'));
    }
    next();
  };
}
