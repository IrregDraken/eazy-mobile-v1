import { z } from 'zod';
import { paginationQuerySchema } from '../../utils/pagination.js';

const uuidSchema = z.string().uuid();
const usernameSchema = z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,32}$/, 'Invalid username');
const textBodySchema = z.string().trim().min(1, 'Message body cannot be empty').max(10_000, 'Message body is too long');

export const createConversationSchema = z.object({ username: usernameSchema }).strict();
export const chatPaginationSchema = paginationQuerySchema.omit({ cursor: true }).strict();
export const conversationParamsSchema = z.object({ conversationId: uuidSchema }).strict();
export const messageParamsSchema = z.object({ messageId: uuidSchema }).strict();
export const createMessageSchema = z.object({ body: textBodySchema, replyToMessageId: uuidSchema.optional() }).strict();
export const editMessageSchema = z.object({ body: textBodySchema }).strict();
export const reportMessageSchema = z.object({ reason: z.string().trim().min(3).max(1000) }).strict();
export const readStateSchema = z.object({ lastReadMessageId: uuidSchema.optional() }).strict().default({});

export const supportedReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏', '👏', '🔥'] as const;
export const reactionSchema = z.enum(supportedReactions);
export const addReactionSchema = z.object({ reaction: reactionSchema }).strict();
export const reactionParamsSchema = z.object({ messageId: uuidSchema, reaction: reactionSchema }).strict();

export { uuidSchema };
