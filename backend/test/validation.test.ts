import assert from 'node:assert/strict';
import test from 'node:test';
import { z } from 'zod';
import { validate } from '../src/middleware/validate.js';
import { AppError } from '../src/middleware/errors.js';

function run(part: 'body' | 'query' | 'params', value: unknown): Promise<{ error?: unknown; request: Record<string, unknown> }> {
  return new Promise(resolve => {
    const request: Record<string, unknown> = { [part]: value };
    validate(part, z.object({ name: z.string().min(2) }))(request as never, {} as never, error => resolve({ error, request }));
  });
}

test('valid body is parsed and forwarded', async () => {
  const result = await run('body', { name: 'Eazy' });
  assert.equal(result.error, undefined);
  assert.deepEqual(result.request.body, { name: 'Eazy' });
});

test('invalid body returns validation error', async () => {
  const result = await run('body', { name: 'x' });
  assert.ok(result.error instanceof AppError && result.error.code === 'VALIDATION_ERROR');
});

test('invalid query and params return validation errors', async () => {
  const query = await run('query', { name: 4 });
  const params = await run('params', {});
  assert.ok(query.error instanceof AppError && query.error.code === 'VALIDATION_ERROR');
  assert.ok(params.error instanceof AppError && params.error.code === 'VALIDATION_ERROR');
});
