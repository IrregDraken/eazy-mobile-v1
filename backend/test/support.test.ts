import assert from 'node:assert/strict';
import test from 'node:test';
import { SupportRepository } from '../src/modules/support/repository.js';
import { SupportService } from '../src/modules/support/service.js';
import { AppError } from '../src/middleware/errors.js';

test('support contact is sourced from configuration and is null when not configured', () => {
  const repository = {} as SupportRepository;
  assert.deepEqual(new SupportService(repository, 'help@example.com').getConfig(), {
    supportEmail: 'help@example.com'
  });
  assert.deepEqual(new SupportService(repository).getConfig(), { supportEmail: null });
});

test('support reports are persisted for the authenticated user and return a reference', async () => {
  const calls: Array<{ sql: string; values: unknown[] }> = [];
  const pool = {
    query: async (sql: string, values: unknown[]) => {
      calls.push({ sql, values });
      return { rows: [{ id: 'report-1', status: 'open' }], rowCount: 1 };
    }
  };
  const repository = new SupportRepository(pool as never);
  const service = new SupportService(repository, 'help@example.com');
  const result = await service.createReport('user-1', {
    category: 'bug',
    subject: 'Cannot publish a post',
    description: 'The publish action returns an error after the image upload completes.'
  });
  assert.deepEqual(result, { reportId: 'report-1', status: 'open' });
  assert.match(calls[0]!.sql, /INSERT INTO support_reports/);
  assert.deepEqual(calls[0]!.values, [
    'user-1',
    'bug',
    'Cannot publish a post',
    'The publish action returns an error after the image upload completes.'
  ]);
});

test('support report persistence failures return a safe service error', async () => {
  const repository = new SupportRepository({
    query: async () => { throw new Error('database credentials must not leak'); }
  } as never);
  const service = new SupportService(repository);
  await assert.rejects(
    () => service.createReport('user-1', {
      category: 'other',
      subject: 'Something is wrong',
      description: 'This report is long enough to pass validation in the route.'
    }),
    (error: unknown) => error instanceof AppError &&
      error.code === 'SERVICE_UNAVAILABLE' &&
      !error.message.includes('database credentials')
  );
});
