import { z } from 'zod';
import { paginationQuerySchema } from '../../utils/pagination.js';

const uuidSchema = z.string().guid();
const usernameSchema = z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,32}$/, 'Invalid username');
const textBodySchema = z.string().trim().min(1, 'Message body cannot be empty').max(10_000, 'Message body is too long');

export const createConversationSchema = z.object({ username: usernameSchema }).strict();
export const chatPaginationSchema = paginationQuerySchema.omit({ cursor: true }).strict();
export const conversationParamsSchema = z.object({ conversationId: uuidSchema }).strict();
export const messageParamsSchema = z.object({ messageId: uuidSchema }).strict();
const attachmentSchema = z.object({
  storageKey: z.string().trim().min(1).max(1024),
  contentType: z.string().trim().min(1).max(100),
  byteSize: z.number().int().nonnegative().max(25 * 1024 * 1024)
}).strict();
export const createMessageSchema = z.object({
  body: textBodySchema.optional(),
  replyToMessageId: uuidSchema.optional(),
  attachments: z.array(attachmentSchema).max(10).optional()
}).strict().refine(value => Boolean(value.body?.trim()) || Boolean(value.attachments?.length), 'Message needs text or at least one attachment');
export const editMessageSchema = z.object({ body: textBodySchema }).strict();
export const reportMessageSchema = z.object({ reason: z.string().trim().min(3).max(1000) }).strict();
export const readStateSchema = z.object({ lastReadMessageId: uuidSchema.optional() }).strict().default({});

export const supportedReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'] as const;
export const reactionSchema = z.enum(supportedReactions);
export const addReactionSchema = z.object({ reaction: reactionSchema }).strict();
export const reactionParamsSchema = z.object({ messageId: uuidSchema, reaction: reactionSchema }).strict();

export { uuidSchema };
