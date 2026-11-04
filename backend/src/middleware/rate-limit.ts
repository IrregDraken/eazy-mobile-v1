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
    const keys = [`${policy.name}:ip:${request.ip}`];
    const userId = request.auth?.userId;
    if (userId) keys.push(`${policy.name}:user:${userId}`);

    // Enforce both network and authenticated-user budgets. An attacker cannot
    // evade a user limit by changing IPs or exhaust every account on one IP.
    const results = keys.map(key => limiter.consume(key, policy.max, policy.windowMs));
    const remaining = Math.min(...results.map(result => result.remaining));
    const blocked = results.filter(result => !result.allowed);
    response.setHeader('x-rate-limit-limit', policy.max);
    response.setHeader('x-rate-limit-remaining', remaining);
    if (blocked.length > 0) {
      const retryAfterMs = Math.max(...blocked.map(result => result.retryAfterMs));
      response.setHeader('retry-after', Math.ceil(retryAfterMs / 1000));
      return next(new AppError('RATE_LIMITED', 'Too many requests'));
    }
    next();
  };
}
