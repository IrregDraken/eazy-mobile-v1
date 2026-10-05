import { z } from 'zod';

export const paginationQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().trim().min(1).optional()
});

export type Pagination = z.infer<typeof paginationQuerySchema>;

export function paginationMeta(input: Pagination, total?: number) {
  return {
    page: input.page,
    limit: input.limit,
    cursor: input.cursor ?? null,
    ...(total === undefined ? {} : { total, pages: Math.ceil(total / input.limit) })
  };
}
