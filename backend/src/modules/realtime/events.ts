import { z } from 'zod';
import type { ChatMessage, ChatParticipant, ChatReadState } from '../chat/types.js';
import type { NotificationProjection } from '../notifications/repository.js';

const uuid = z.string().uuid();
const participant = z.object({ username: z.string(), displayName: z.string(), avatarUrl: z.string().nullable() }).strict();
const chatMessage = z.object({
  id: uuid,
  conversationId: uuid,
  sender: participant.nullable(),
  body: z.string().nullable(),
  status: z.enum(['sent', 'edited', 'deleted']),
  createdAt: z.string(),
  updatedAt: z.string(),
  deletedAt: z.string().nullable(),
  replyToMessageId: uuid.nullable(),
  replyTo: z.object({ id: uuid, body: z.string().nullable(), status: z.enum(['sent', 'edited', 'deleted']) }).strict().nullable(),
  attachments: z.array(z.object({ id: uuid, contentType: z.string(), byteSize: z.number().int(), createdAt: z.string() }).strict()),
  reactions: z.array(z.object({ reaction: z.string(), count: z.number().int().nonnegative(), reactedByMe: z.boolean() }).strict())
}).strict();
const notification = z.object({
  id: uuid,
  type: z.enum(['follow', 'like', 'comment', 'message', 'order', 'payment', 'system']),
  actor: participant.nullable(),
  title: z.string().nullable(),
  body: z.string().nullable(),
  entityType: z.string().nullable(),
  entityId: z.string().nullable(),
  isRead: z.boolean(),
  createdAt: z.string()
}).strict();

export const clientMessageSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('subscribe'), channel: z.enum(['user', 'conversation']), id: uuid }).strict(),
  z.object({ type: z.literal('unsubscribe'), channel: z.enum(['user', 'conversation']), id: uuid }).strict()
]);

export const realtimeEventSchema = z.discriminatedUnion('event', [
  z.object({ event: z.literal('message.created'), data: z.object({ message: chatMessage }).strict() }).strict(),
  z.object({ event: z.literal('message.reaction.created'), data: z.object({ conversationId: uuid, messageId: uuid, reaction: z.string().min(1).max(32) }).strict() }).strict(),
  z.object({ event: z.literal('message.reaction.deleted'), data: z.object({ conversationId: uuid, messageId: uuid, reaction: z.string().min(1).max(32) }).strict() }).strict(),
  z.object({ event: z.literal('message.read'), data: z.object({ conversationId: uuid, lastReadMessageId: uuid.nullable(), readAt: z.string(), reader: participant }).strict() }).strict(),
  z.object({ event: z.literal('notification.created'), data: z.object({ notification }).strict() }).strict()
]);

export type ClientMessage = z.infer<typeof clientMessageSchema>;
export type RealtimeEvent = z.infer<typeof realtimeEventSchema>;
export type RealtimeChannel = ClientMessage['channel'];
export type RealtimeEventName = RealtimeEvent['event'];
export type RealtimePayloads = { ChatMessage: ChatMessage; ChatParticipant: ChatParticipant; ChatReadState: ChatReadState; NotificationProjection: NotificationProjection };

export function parseClientMessage(raw: string): ClientMessage | null {
  try {
    const parsed = clientMessageSchema.safeParse(JSON.parse(raw) as unknown);
    return parsed.success ? parsed.data : null;
  } catch {
    return null;
  }
}

export function clientFrameError(raw: string): 'invalid_message' | 'invalid_subscription' {
  try {
    const value = JSON.parse(raw) as unknown;
    if (value && typeof value === 'object' && !Array.isArray(value) && 'type' in value) {
      const type = (value as { type?: unknown }).type;
      if (type === 'subscribe' || type === 'unsubscribe') return 'invalid_subscription';
    }
  } catch { /* malformed JSON */ }
  return 'invalid_message';
}

export function safeEvent(event: RealtimeEvent): RealtimeEvent {
  return realtimeEventSchema.parse(event);
}

export function eventEnvelope(event: RealtimeEvent) {
  const valid = safeEvent(event);
  return { type: 'event' as const, event: valid.event, data: valid.data };
}

export function eventConversationId(event: RealtimeEvent): string | null {
  switch (event.event) {
    case 'message.created': return event.data.message.conversationId;
    case 'message.reaction.created':
    case 'message.reaction.deleted':
    case 'message.read': return event.data.conversationId;
    case 'notification.created': return null;
  }
}

export function isSensitiveFieldAbsent(event: RealtimeEvent): boolean {
  const sensitive = /^(firebaseUid|firebase_uid|sessionToken|deviceToken|password|providerCredential|email|phone)$/i;
  const visit = (value: unknown): boolean => {
    if (!value || typeof value !== 'object') return true;
    if (Array.isArray(value)) return value.every(visit);
    return Object.entries(value).every(([key, child]) => !sensitive.test(key) && visit(child));
  };
  return visit(event);
}

export const REALTIME_LIMITS = {
  maxFrameBytes: 4096,
  heartbeatMs: 60_000,
  staleAfterMs: 120_000,
  maxConnectionsPerUser: 5,
  maxSubscriptionsPerConnection: 100,
  malformedFramesBeforeClose: 3,
  framesPerWindow: 120,
  subscriptionsPerWindow: 60,
  operationWindowMs: 60_000,
  maxAuthHeaderLength: 8192
} as const;

export const REALTIME_EVENTS: readonly RealtimeEventName[] = [
  'message.created',
  'message.reaction.created',
  'message.reaction.deleted',
  'message.read',
  'notification.created'
];

export function isUuid(value: string): boolean {
  return uuid.safeParse(value).success;
}

export function safeError(code: 'unauthorized' | 'forbidden' | 'invalid_message' | 'invalid_subscription' | 'not_found' | 'rate_limited' | 'internal_error') {
  const messages = {
    unauthorized: 'Authentication required',
    forbidden: 'This subscription is unavailable',
    invalid_message: 'Invalid realtime message',
    invalid_subscription: 'Invalid realtime subscription',
    not_found: 'This subscription is unavailable',
    rate_limited: 'Realtime rate limit exceeded',
    internal_error: 'Realtime operation failed'
  } as const;
  return { type: 'error' as const, code, message: messages[code] };
}

export function getClientErrorCode(error: unknown): 'unauthorized' | 'forbidden' | 'not_found' | 'rate_limited' | 'internal_error' {
  const code = error && typeof error === 'object' && 'code' in error ? (error as { code?: unknown }).code : undefined;
  if (code === 'UNAUTHORIZED') return 'unauthorized';
  if (code === 'FORBIDDEN') return 'forbidden';
  if (code === 'NOT_FOUND') return 'not_found';
  if (code === 'RATE_LIMITED') return 'rate_limited';
  return 'internal_error';
}

export function safeUserId(userId: string): string {
  if (!isUuid(userId)) throw new Error('Invalid Eazy user identity');
  return userId.toLowerCase();
}

export function isSafeMessagePayload(value: unknown): value is ChatMessage {
  return chatMessage.safeParse(value).success;
}

export function isSafeNotificationPayload(value: unknown): value is NotificationProjection {
  return notification.safeParse(value).success;
}

export function frameBytes(value: Buffer | ArrayBuffer | Buffer[]): number {
  if (Buffer.isBuffer(value)) return value.byteLength;
  if (Array.isArray(value)) return value.reduce((sum, part) => sum + part.byteLength, 0);
  return value.byteLength;
}

export function parseBearerToken(value: string | string[] | undefined): string | null {
  if (typeof value !== 'string' || value.length > REALTIME_LIMITS.maxAuthHeaderLength) return null;
  const match = value.match(/^Bearer ([A-Za-z0-9._~+/-]+=*)$/i);
  return match?.[1] ?? null;
}

export function pathIsRealtime(url: string | undefined): boolean {
  if (!url) return false;
  try {
    const parsed = new URL(url, 'http://localhost');
    return parsed.pathname === '/v1/realtime' && !parsed.search && !parsed.hash;
  } catch {
    return false;
  }
}

export function originAllowed(origin: string | undefined, configured: string): boolean {
  if (!origin || configured === '*') return true;
  return configured.split(',').map(value => value.trim()).includes(origin);
}

export function normalizeChannel(channel: RealtimeChannel, id: string): string {
  return `${channel}:${id.toLowerCase()}`;
}

export function eventForMessage(message: ChatMessage): RealtimeEvent {
  return { event: 'message.created', data: { message } };
}

export function eventForReaction(event: 'message.reaction.created' | 'message.reaction.deleted', conversationId: string, messageId: string, reaction: string): RealtimeEvent {
  return { event, data: { conversationId, messageId, reaction } };
}

export function eventForRead(conversationId: string, lastReadMessageId: string | null, readAt: string, reader: ChatParticipant): RealtimeEvent {
  return { event: 'message.read', data: { conversationId, lastReadMessageId, readAt, reader } };
}

export function eventForNotification(value: NotificationProjection): RealtimeEvent {
  return { event: 'notification.created', data: { notification: value } };
}
