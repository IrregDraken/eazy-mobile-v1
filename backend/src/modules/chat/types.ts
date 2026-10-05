export interface ChatParticipant {
  username: string;
  displayName: string;
  avatarUrl: string | null;
}

export interface ChatConversation {
  id: string;
  kind: 'direct';
  createdAt: string;
  updatedAt: string;
  participants: ChatParticipant[];
  latestMessage: {
    id: string;
    body: string | null;
    status: 'sent' | 'edited' | 'deleted';
    createdAt: string;
  } | null;
  unreadCount: number;
  lastReadAt: string | null;
}

export interface ChatReactionSummary {
  reaction: string;
  count: number;
  reactedByMe: boolean;
}

export interface ChatAttachmentSummary {
  id: string;
  contentType: string;
  byteSize: number;
  createdAt: string;
}

export interface ChatMessage {
  id: string;
  conversationId: string;
  sender: ChatParticipant | null;
  body: string | null;
  status: 'sent' | 'edited' | 'deleted';
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  replyToMessageId: string | null;
  replyTo: { id: string; body: string | null; status: 'sent' | 'edited' | 'deleted' } | null;
  attachments: ChatAttachmentSummary[];
  reactions: ChatReactionSummary[];
}

export interface ChatPage<T> {
  items: T[];
  meta: { page: number; limit: number; cursor: string | null; total: number; pages: number };
}

export interface ChatReadState {
  conversationId: string;
  lastReadMessageId: string | null;
  readAt: string;
}

export interface ChatTarget {
  id: string;
  username: string;
}

export interface ChatReadInput {
  lastReadMessageId?: string;
}

export interface ChatCreateMessageInput {
  body: string;
  replyToMessageId?: string;
}

export interface ChatEditMessageInput {
  body: string;
}

export interface ChatMessagePageInput {
  page: number;
  limit: number;
  cursor?: string;
}

export interface ChatConversationPageInput {
  page: number;
  limit: number;
  cursor?: string;
}

export interface ChatPageResult<T> {
  items: T[];
  total: number;
}

export interface ChatReadRecord {
  conversation_id: string;
  last_read_message_id: string | null;
  read_at: string;
}

export interface ChatConversationRecord {
  id: string;
  kind: 'direct';
  createdAt: string;
  updatedAt: string;
  participants: unknown;
  latestMessage: unknown;
  unreadCount: number | string;
  lastReadAt: string | null;
}

export interface ChatMessageRecord {
  id: string;
  conversationId: string;
  sender: unknown;
  body: string | null;
  status: 'sent' | 'edited' | 'deleted';
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
  replyToMessageId: string | null;
  replyTo: unknown;
  attachments: unknown;
  reactions: unknown;
}

export interface ChatBlockChecker {
  isBlocked(client: import('pg').Pool | import('pg').PoolClient, firstUserId: string, secondUserId: string): Promise<boolean>;
}

export interface ChatRepositoryContract {
  findTargetByUsername(client: import('pg').Pool | import('pg').PoolClient, username: string): Promise<ChatTarget | null>;
  lockDirectConversation(client: import('pg').PoolClient, firstUserId: string, secondUserId: string): Promise<void>;
  findDirectConversation(client: import('pg').PoolClient, firstUserId: string, secondUserId: string): Promise<string | null>;
  createDirectConversation(client: import('pg').PoolClient, creatorId: string, otherUserId: string): Promise<string>;
  isActiveMember(client: import('pg').Pool | import('pg').PoolClient, conversationId: string, userId: string): Promise<boolean>;
  getOtherParticipantIds(client: import('pg').Pool | import('pg').PoolClient, conversationId: string, userId: string): Promise<string[]>;
  getActiveParticipantProfile(client: import('pg').Pool | import('pg').PoolClient, conversationId: string, userId: string): Promise<ChatParticipant | null>;
  listConversations(userId: string, page: number, limit: number): Promise<ChatPageResult<ChatConversation>>;
  getConversation(userId: string, conversationId: string): Promise<ChatConversation | null>;
  listMessages(userId: string, conversationId: string, page: number, limit: number): Promise<ChatPageResult<ChatMessage>>;
  getMessageForMember(client: import('pg').Pool | import('pg').PoolClient, messageId: string, userId: string): Promise<ChatMessage | null>;
  replyBelongsToConversation(client: import('pg').Pool | import('pg').PoolClient, replyId: string, conversationId: string, userId: string): Promise<boolean>;
  createMessage(client: import('pg').PoolClient, conversationId: string, senderId: string, body: string, replyToMessageId?: string): Promise<string | null>;
  getMessageAsSender(client: import('pg').PoolClient, messageId: string, senderId: string): Promise<Pick<ChatMessage, 'id' | 'status' | 'deletedAt'> | null>;
  softDeleteMessage(client: import('pg').PoolClient, messageId: string, senderId: string): Promise<boolean>;
  editMessage(client: import('pg').PoolClient, messageId: string, senderId: string, body: string): Promise<boolean>;
  getLatestMessageId(client: import('pg').Pool | import('pg').PoolClient, conversationId: string, userId: string): Promise<string | null>;
  markRead(client: import('pg').PoolClient, conversationId: string, userId: string, messageId: string | null): Promise<ChatReadState | null>;
  addReaction(client: import('pg').PoolClient, messageId: string, userId: string, reaction: string): Promise<boolean>;
  removeReaction(client: import('pg').PoolClient, messageId: string, userId: string, reaction: string): Promise<boolean>;
  getMessageConversationForMember(client: import('pg').Pool | import('pg').PoolClient, messageId: string, userId: string): Promise<string | null>;
  createMessageReport(client: import('pg').PoolClient, messageId: string, reporterId: string, reason: string): Promise<string | null>;
}

export function parseJsonField<T>(value: unknown, fallback: T): T {
  if (value === null || value === undefined) return fallback;
  if (typeof value === 'string') {
    try { return JSON.parse(value) as T; } catch { return fallback; }
  }
  return value as T;
}

export function normalizeParticipant(value: unknown): ChatParticipant | null {
  if (!value || typeof value !== 'object') return null;
  const candidate = value as Partial<ChatParticipant>;
  if (typeof candidate.username !== 'string' || typeof candidate.displayName !== 'string') return null;
  return { username: candidate.username, displayName: candidate.displayName, avatarUrl: typeof candidate.avatarUrl === 'string' ? candidate.avatarUrl : null };
}

export function normalizeConversation(row: ChatConversationRecord): ChatConversation {
  const participants = parseJsonField<unknown[]>(row.participants, []);
  const latestMessage = parseJsonField<ChatConversation['latestMessage']>(row.latestMessage, null);
  return {
    id: row.id,
    kind: 'direct',
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    participants: participants.map(normalizeParticipant).filter((participant): participant is ChatParticipant => participant !== null),
    latestMessage,
    unreadCount: Number(row.unreadCount),
    lastReadAt: row.lastReadAt
  };
}

export function normalizeMessage(row: ChatMessageRecord): ChatMessage {
  return {
    id: row.id,
    conversationId: row.conversationId,
    sender: normalizeParticipant(row.sender),
    body: row.body,
    status: row.status,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    replyToMessageId: row.replyToMessageId,
    replyTo: parseJsonField<ChatMessage['replyTo']>(row.replyTo, null),
    attachments: parseJsonField<ChatMessage['attachments']>(row.attachments, []),
    reactions: parseJsonField<ChatMessage['reactions']>(row.reactions, [])
  };
}
