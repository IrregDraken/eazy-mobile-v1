import { z } from 'zod';

export const createSessionSchema = z.object({}).strict();
export const assistSessionParamsSchema = z.object({ id: z.string().uuid() }).strict();
export const assistHistoryQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20)
}).strict();
export const assistMessageSchema = z.object({ content: z.string().trim().min(1).max(4_000) }).strict();

export type AssistHistoryQuery = z.infer<typeof assistHistoryQuerySchema>;
export type AssistMessageInput = z.infer<typeof assistMessageSchema>;
