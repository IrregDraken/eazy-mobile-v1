import { z } from 'zod';
import { AppError } from '../../middleware/errors.js';

export const MAX_ASSIST_RESPONSE_CHARS = 4_000;

const answerSchema = z.object({
  type: z.literal('answer'),
  text: z.string().trim().min(1).max(MAX_ASSIST_RESPONSE_CHARS)
}).strict();

const toolCallSchema = z.object({
  type: z.literal('tool_call'),
  name: z.enum(['search_products', 'translate_text']),
  arguments: z.unknown()
}).strict();

export type AssistDecision = z.infer<typeof answerSchema> | z.infer<typeof toolCallSchema>;

export function parseDecision(text: string, allowedTools: readonly string[] = ['search_products']): AssistDecision {
  try {
    const parsed: unknown = JSON.parse(text);
    const decision = z.union([answerSchema, toolCallSchema]).safeParse(parsed);
    if (!decision.success) throw providerFailure();
    if (decision.data.type === 'tool_call' && !allowedTools.includes(decision.data.name)) throw providerFailure();
    return decision.data;
  } catch {
    throw providerFailure();
  }
}

export function providerFailure(): AppError {
  return new AppError('SERVICE_UNAVAILABLE', 'Eazy Assist provider returned an unavailable or invalid response');
}
