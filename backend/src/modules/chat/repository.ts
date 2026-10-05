import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import { lockUserPair } from '../social/pair-lock.js';
import {
  normalizeConversation,
  normalizeMessage,
  type ChatConversation,
  type ChatConversationRecord,
  type ChatMessage,
  type ChatMessageRecord,
  type ChatPageResult,
  type ChatReadRecord,
  type ChatReadState,
  type ChatTarget
} from './types.js';

type DbHandle = Pool | DbClient;

const conversationProjection = `
  SELECT c.id, c.kind, c.created_at AS "createdAt", c.updated_at AS "updatedAt",
    COALESCE(participant_rows.items, '[]'::json) AS participants,
    latest.id AS "latestMessageId",
    CASE WHEN latest.id IS NULL THEN NULL ELSE json_build_object(
      'id', latest.id,
      'body', CASE WHEN latest.status = 'deleted' THEN NULL ELSE latest.body END,
      'status', latest.status,
      'createdAt', latest.created_at
    ) END AS "latestMessage",
    COALESCE(unread.unread_count, 0)::int AS "unreadCount",
    read_state.read_at AS "lastReadAt"
  FROM conversations c
  JOIN conversation_members current_member
    ON current_member.conversation_id = c.id AND current_member.user_id = $1 AND current_member.left_at IS NULL
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object(
      'username', p.username,
      'displayName', p.display_name,
      'avatarUrl', p.avatar_url
    ) ORDER BY p.username) AS items
    FROM conversation_members cm
    JOIN profiles p ON p.user_id = cm.user_id
    WHERE cm.conversation_id = c.id AND cm.left_at IS NULL
  ) participant_rows ON true
  LEFT JOIN LATERAL (
    SELECT m.id, m.body, m.status, m.created_at
    FROM messages m
    WHERE m.conversation_id = c.id
    ORDER BY m.created_at DESC, m.id DESC
    LIMIT 1
  ) latest ON true
  LEFT JOIN message_reads read_state ON read_state.conversation_id = c.id AND read_state.user_id = $1
  LEFT JOIN messages last_read
    ON last_read.id = read_state.last_read_message_id AND last_read.conversation_id = c.id
  LEFT JOIN LATERAL (
    SELECT count(*)::int AS unread_count
    FROM messages unread
    WHERE unread.conversation_id = c.id
      AND unread.sender_id <> $1
      AND unread.status <> 'deleted'
      AND (last_read.id IS NULL OR (unread.created_at, unread.id) > (last_read.created_at, last_read.id))
  ) unread ON true
  WHERE c.kind = 'direct'
`;

const messageProjectionJoins = `
  FROM messages m
  JOIN conversations c ON c.id = m.conversation_id AND c.kind = 'direct'
  JOIN conversation_members member
    ON member.conversation_id = c.id AND member.user_id = $1 AND member.left_at IS NULL
  LEFT JOIN profiles sender_profile ON sender_profile.user_id = m.sender_id
  LEFT JOIN messages reply
    ON reply.id = m.reply_to_message_id AND reply.conversation_id = m.conversation_id
`;

const messageProjectionFields = `
  m.id,
  m.conversation_id AS "conversationId",
  CASE WHEN sender_profile.username IS NULL THEN NULL ELSE json_build_object(
    'username', sender_profile.username,
    'displayName', sender_profile.display_name,
    'avatarUrl', sender_profile.avatar_url
  ) END AS sender,
  CASE WHEN m.status = 'deleted' THEN NULL ELSE m.body END AS body,
  m.status,
  m.created_at AS "createdAt",
  m.updated_at AS "updatedAt",
  m.deleted_at AS "deletedAt",
  m.reply_to_message_id AS "replyToMessageId",
  CASE WHEN reply.id IS NULL THEN NULL ELSE json_build_object(
    'id', reply.id,
    'body', CASE WHEN reply.status = 'deleted' THEN NULL ELSE reply.body END,
    'status', reply.status
  ) END AS "replyTo",
  CASE WHEN m.status = 'deleted' THEN '[]'::json ELSE COALESCE(attachment_rows.items, '[]'::json) END AS attachments,
  CASE WHEN m.status = 'deleted' THEN '[]'::json ELSE COALESCE(reaction_rows.items, '[]'::json) END AS reactions
`;

const messageProjectionLateral = `
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object(
      'id', a.id,
      'contentType', a.content_type,
      'byteSize', a.byte_size,
      'createdAt', a.created_at
    ) ORDER BY a.created_at, a.id) AS items
    FROM message_attachments a WHERE a.message_id = m.id
  ) attachment_rows ON true
  LEFT JOIN LATERAL (
    SELECT json_agg(json_build_object(
      'reaction', grouped.reaction,
      'count', grouped.reaction_count,
      'reactedByMe', grouped.reacted_by_me
    ) ORDER BY grouped.reaction) AS items
    FROM (
      SELECT r.reaction, count(*)::int AS reaction_count, bool_or(r.user_id = $1) AS reacted_by_me
      FROM message_reactions r WHERE r.message_id = m.id GROUP BY r.reaction
    ) grouped
  ) reaction_rows ON true
`;

export class ChatRepository {
  constructor(private readonly pool: Pool) {}

  async findTargetByUsername(client: DbHandle, username: string): Promise<ChatTarget | null> {
    const result = await client.query<ChatTarget>(
      `SELECT u.id, p.username FROM users u
       JOIN profiles p ON p.user_id = u.id
       WHERE p.username = $1 AND u.status = 'active' LIMIT 1`,
      [username]
    );
    return result.rows[0] ?? null;
  }

  async lockDirectConversation(client: DbClient, firstUserId: string, secondUserId: string): Promise<void> {
    await lockUserPair(client, firstUserId, secondUserId);
  }

  async findDirectConversation(client: DbClient, firstUserId: string, secondUserId: string): Promise<string | null> {
    const result = await client.query<{ id: string }>(
      `SELECT c.id
       FROM conversations c
       JOIN conversation_members first_member
         ON first_member.conversation_id = c.id AND first_member.user_id = $1 AND first_member.left_at IS NULL
       JOIN conversation_members second_member
         ON second_member.conversation_id = c.id AND second_member.user_id = $2 AND second_member.left_at IS NULL
       WHERE c.kind = 'direct'
         AND (SELECT count(*) FROM conversation_members active_members
              WHERE active_members.conversation_id = c.id AND active_members.left_at IS NULL) = 2
       ORDER BY c.created_at, c.id
       LIMIT 1
       FOR UPDATE OF c`,
      [firstUserId, secondUserId]
    );
    return result.rows[0]?.id ?? null;
  }

  async createDirectConversation(client: DbClient, creatorId: string, otherUserId: string): Promise<string> {
    const [lowId, highId] = [creatorId, otherUserId].sort();
    const result = await client.query<{ id: string }>(
      `INSERT INTO conversations (kind, created_by, direct_user_low_id, direct_user_high_id)
       VALUES ('direct', $1, $2, $3)
       ON CONFLICT (direct_user_low_id, direct_user_high_id) WHERE kind = 'direct' DO NOTHING
       RETURNING id`,
      [creatorId, lowId, highId]
    );
    const conversationId = result.rows[0]?.id ?? (await client.query<{ id: string }>(
      `SELECT id FROM conversations
       WHERE kind = 'direct' AND direct_user_low_id = $1 AND direct_user_high_id = $2
       LIMIT 1 FOR UPDATE`,
      [lowId, highId]
    )).rows[0]?.id;
    if (!conversationId) throw new Error('DIRECT_CONVERSATION_CONFLICT');
    if (!result.rows[0]) return conversationId;
    await client.query(
      `INSERT INTO conversation_members (conversation_id, user_id) VALUES ($1, $2), ($1, $3)`,
      [conversationId, creatorId, otherUserId]
    );
    return conversationId;
  }

  async isActiveMember(client: DbHandle, conversationId: string, userId: string): Promise<boolean> {
    const result = await client.query<{ exists: boolean }>(
      `SELECT EXISTS (
         SELECT 1 FROM conversations c
         JOIN conversation_members cm ON cm.conversation_id = c.id
         WHERE c.id = $1 AND c.kind = 'direct' AND cm.user_id = $2 AND cm.left_at IS NULL
       ) AS exists`,
      [conversationId, userId]
    );
    return Boolean(result.rows[0]?.exists);
  }

  async getOtherParticipantIds(client: DbHandle, conversationId: string, userId: string): Promise<string[]> {
    const result = await client.query<{ user_id: string }>(
      `SELECT other_member.user_id FROM conversations c
       JOIN conversation_members current_member
         ON current_member.conversation_id = c.id AND current_member.user_id = $2 AND current_member.left_at IS NULL
       JOIN conversation_members other_member
         ON other_member.conversation_id = c.id AND other_member.left_at IS NULL AND other_member.user_id <> $2
       WHERE c.id = $1 AND c.kind = 'direct' ORDER BY other_member.user_id LIMIT 10`,
      [conversationId, userId]
    );
    return result.rows.map(row => row.user_id);
  }

  async getActiveParticipantProfile(client: DbHandle, conversationId: string, userId: string): Promise<{ username: string; displayName: string; avatarUrl: string | null } | null> {
    const result = await client.query<{ username: string; displayName: string; avatarUrl: string | null }>(
      `SELECT p.username, p.display_name AS "displayName", p.avatar_url AS "avatarUrl"
       FROM conversation_members cm JOIN profiles p ON p.user_id = cm.user_id
       WHERE cm.conversation_id = $1 AND cm.user_id = $2 AND cm.left_at IS NULL LIMIT 1`,
      [conversationId, userId]
    );
    return result.rows[0] ?? null;
  }

  async listConversations(userId: string, page: number, limit: number): Promise<ChatPageResult<ChatConversation>> {
    const count = await this.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM conversations c
       JOIN conversation_members cm ON cm.conversation_id = c.id
       WHERE c.kind = 'direct' AND cm.user_id = $1 AND cm.left_at IS NULL`,
      [userId]
    );
    const result = await this.pool.query<ChatConversationRecord>(
      `${conversationProjection}
       ORDER BY COALESCE(latest.created_at, c.created_at) DESC, c.id DESC
       LIMIT $2 OFFSET $3`,
      [userId, limit, (page - 1) * limit]
    );
    return { items: result.rows.map(normalizeConversation), total: Number(count.rows[0]?.count ?? 0) };
  }

  async getConversation(userId: string, conversationId: string): Promise<ChatConversation | null> {
    const result = await this.pool.query<ChatConversationRecord>(
      `${conversationProjection} AND c.id = $2 LIMIT 1`,
      [userId, conversationId]
    );
    return result.rows[0] ? normalizeConversation(result.rows[0]) : null;
  }

  async listMessages(userId: string, conversationId: string, page: number, limit: number): Promise<ChatPageResult<ChatMessage>> {
    const count = await this.pool.query<{ count: string }>(
      `SELECT count(*)::text AS count FROM messages m
       JOIN conversations c ON c.id = m.conversation_id AND c.kind = 'direct'
       JOIN conversation_members cm ON cm.conversation_id = c.id
       WHERE m.conversation_id = $2 AND cm.user_id = $1 AND cm.left_at IS NULL`,
      [userId, conversationId]
    );
    const result = await this.pool.query<ChatMessageRecord>(
      `SELECT ${messageProjectionFields}
       ${messageProjectionJoins}
       ${messageProjectionLateral}
       WHERE m.conversation_id = $2
       ORDER BY m.created_at DESC, m.id DESC
       LIMIT $3 OFFSET $4`,
      [userId, conversationId, limit, (page - 1) * limit]
    );
    return { items: result.rows.map(normalizeMessage), total: Number(count.rows[0]?.count ?? 0) };
  }

  async getMessageForMember(client: DbHandle, messageId: string, userId: string): Promise<ChatMessage | null> {
    const result = await client.query<ChatMessageRecord>(
      `SELECT ${messageProjectionFields}
       ${messageProjectionJoins}
       ${messageProjectionLateral}
       WHERE m.id = $2 LIMIT 1`,
      [userId, messageId]
    );
    return result.rows[0] ? normalizeMessage(result.rows[0]) : null;
  }

  async replyBelongsToConversation(client: DbHandle, replyId: string, conversationId: string, userId: string): Promise<boolean> {
    const result = await client.query<{ exists: boolean }>(
      `SELECT EXISTS (
         SELECT 1 FROM messages reply
         JOIN conversations c ON c.id = reply.conversation_id AND c.kind = 'direct'
         JOIN conversation_members cm ON cm.conversation_id = c.id
         WHERE reply.id = $1 AND reply.conversation_id = $2 AND cm.user_id = $3 AND cm.left_at IS NULL
       ) AS exists`,
      [replyId, conversationId, userId]
    );
    return Boolean(result.rows[0]?.exists);
  }

  async createMessage(client: DbClient, conversationId: string, senderId: string, body: string, replyToMessageId?: string): Promise<string | null> {
    const result = await client.query<{ id: string }>(
      `INSERT INTO messages (conversation_id, sender_id, body, reply_to_message_id)
       SELECT $1, $2, $3, $4
       WHERE EXISTS (
         SELECT 1 FROM conversations c
         JOIN conversation_members cm ON cm.conversation_id = c.id
         WHERE c.id = $1 AND c.kind = 'direct' AND cm.user_id = $2 AND cm.left_at IS NULL
       )
       RETURNING id`,
      [conversationId, senderId, body, replyToMessageId ?? null]
    );
    return result.rows[0]?.id ?? null;
  }

  async getMessageAsSender(client: DbClient, messageId: string, senderId: string): Promise<Pick<ChatMessage, 'id' | 'status' | 'deletedAt'> | null> {
    const result = await client.query<{ id: string; status: ChatMessage['status']; deletedAt: string | null }>(
      `SELECT m.id, m.status, m.deleted_at AS "deletedAt"
       FROM messages m
       JOIN conversations c ON c.id = m.conversation_id AND c.kind = 'direct'
       JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.left_at IS NULL
       WHERE m.id = $1 AND m.sender_id = $2 AND cm.user_id = $2
       LIMIT 1 FOR UPDATE OF m`,
      [messageId, senderId]
    );
    return result.rows[0] ?? null;
  }

  async softDeleteMessage(client: DbClient, messageId: string, senderId: string): Promise<boolean> {
    const result = await client.query(
      `UPDATE messages m SET body = NULL, status = 'deleted', deleted_at = COALESCE(m.deleted_at, now())
       WHERE m.id = $1 AND m.sender_id = $2 AND m.status <> 'deleted'
         AND EXISTS (
           SELECT 1 FROM conversations c JOIN conversation_members cm ON cm.conversation_id = c.id
           WHERE c.id = m.conversation_id AND c.kind = 'direct' AND cm.user_id = $2 AND cm.left_at IS NULL
         )
       RETURNING m.id`,
      [messageId, senderId]
    );
    return Boolean(result.rowCount);
  }

  async editMessage(client: DbClient, messageId: string, senderId: string, body: string): Promise<boolean> {
    const result = await client.query(
      `UPDATE messages m SET body = $3, status = 'edited'
       WHERE m.id = $1 AND m.sender_id = $2 AND m.status <> 'deleted'
         AND EXISTS (
           SELECT 1 FROM conversations c JOIN conversation_members cm ON cm.conversation_id = c.id
           WHERE c.id = m.conversation_id AND c.kind = 'direct' AND cm.user_id = $2 AND cm.left_at IS NULL
         )
       RETURNING m.id`,
      [messageId, senderId, body]
    );
    return Boolean(result.rowCount);
  }

  async getLatestMessageId(client: DbHandle, conversationId: string, userId: string): Promise<string | null> {
    const result = await client.query<{ id: string }>(
      `SELECT m.id FROM messages m
       JOIN conversations c ON c.id = m.conversation_id AND c.kind = 'direct'
       JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $2 AND cm.left_at IS NULL
       WHERE m.conversation_id = $1
       ORDER BY m.created_at DESC, m.id DESC LIMIT 1`,
      [conversationId, userId]
    );
    return result.rows[0]?.id ?? null;
  }

  async markRead(client: DbClient, conversationId: string, userId: string, messageId: string | null): Promise<ChatReadState | null> {
    const result = await client.query<ChatReadRecord>(
      `WITH allowed AS (
         SELECT $1::uuid AS conversation_id, $2::uuid AS user_id, $3::uuid AS last_read_message_id
         WHERE EXISTS (
         SELECT 1 FROM conversations c
         JOIN conversation_members cm ON cm.conversation_id = c.id
         WHERE c.id = $1 AND c.kind = 'direct' AND cm.user_id = $2 AND cm.left_at IS NULL
         )
         AND ($3::uuid IS NULL OR EXISTS (
           SELECT 1 FROM messages m WHERE m.id = $3 AND m.conversation_id = $1
         ))
       ), changed AS (
         INSERT INTO message_reads (conversation_id, user_id, last_read_message_id, read_at)
         SELECT conversation_id, user_id, last_read_message_id, now() FROM allowed
         ON CONFLICT (conversation_id, user_id) DO UPDATE
         SET last_read_message_id = COALESCE(EXCLUDED.last_read_message_id, message_reads.last_read_message_id), read_at = now()
         WHERE EXCLUDED.last_read_message_id IS NULL
            OR message_reads.last_read_message_id IS NULL
            OR EXISTS (
              SELECT 1 FROM messages next_read
              JOIN messages current_read ON current_read.id = message_reads.last_read_message_id
              WHERE next_read.id = EXCLUDED.last_read_message_id
                AND (next_read.created_at, next_read.id) >= (current_read.created_at, current_read.id)
            )
         RETURNING conversation_id, last_read_message_id, read_at
       )
       SELECT conversation_id, last_read_message_id, read_at FROM changed
       UNION ALL
       SELECT existing.conversation_id, existing.last_read_message_id, existing.read_at
       FROM message_reads existing
       WHERE existing.conversation_id = $1 AND existing.user_id = $2
         AND EXISTS (SELECT 1 FROM allowed)
         AND NOT EXISTS (SELECT 1 FROM changed)
       LIMIT 1`,
      [conversationId, userId, messageId]
    );
    const row = result.rows[0];
    return row ? { conversationId: row.conversation_id, lastReadMessageId: row.last_read_message_id, readAt: row.read_at } : null;
  }

  async addReaction(client: DbClient, messageId: string, userId: string, reaction: string): Promise<boolean> {
    const result = await client.query(
      `INSERT INTO message_reactions (message_id, user_id, reaction)
       SELECT m.id, $2, $3
       FROM messages m
       JOIN conversations c ON c.id = m.conversation_id AND c.kind = 'direct'
       JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $2 AND cm.left_at IS NULL
       WHERE m.id = $1
       ON CONFLICT (message_id, user_id, reaction) DO NOTHING
       RETURNING message_id`,
      [messageId, userId, reaction]
    );
    return Boolean(result.rowCount);
  }

  async removeReaction(client: DbClient, messageId: string, userId: string, reaction: string): Promise<boolean> {
    const result = await client.query(
      `DELETE FROM message_reactions r
       USING messages m, conversations c, conversation_members cm
       WHERE r.message_id = m.id AND m.conversation_id = c.id AND c.kind = 'direct'
         AND cm.conversation_id = c.id AND cm.user_id = $2 AND cm.left_at IS NULL
         AND m.id = $1 AND r.user_id = $2 AND r.reaction = $3
       RETURNING r.message_id`,
      [messageId, userId, reaction]
    );
    return Boolean(result.rowCount);
  }

  async getMessageConversationForMember(client: DbHandle, messageId: string, userId: string): Promise<string | null> {
    const result = await client.query<{ conversation_id: string }>(
      `SELECT m.conversation_id FROM messages m
       JOIN conversations c ON c.id = m.conversation_id AND c.kind = 'direct'
       JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $2 AND cm.left_at IS NULL
       WHERE m.id = $1 LIMIT 1`,
      [messageId, userId]
    );
    return result.rows[0]?.conversation_id ?? null;
  }

  async createMessageReport(client: DbClient, messageId: string, reporterId: string, reason: string): Promise<string | null> {
    const result = await client.query<{ id: string }>(
      `INSERT INTO reports (reporter_id, resource_type, resource_id, reason)
       SELECT $2, 'message', m.id, $3
       FROM messages m
       JOIN conversations c ON c.id = m.conversation_id AND c.kind = 'direct'
       JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = $2 AND cm.left_at IS NULL
       WHERE m.id = $1
       RETURNING id`,
      [messageId, reporterId, reason]
    );
    return result.rows[0]?.id ?? null;
  }
}

export function toConversation(row: ChatConversationRecord): ChatConversation { return normalizeConversation(row); }
export function toMessage(row: ChatMessageRecord): ChatMessage { return normalizeMessage(row); }
