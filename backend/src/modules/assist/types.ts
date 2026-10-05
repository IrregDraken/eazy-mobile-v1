export type AssistRole = 'user' | 'assistant';

export interface AssistSession {
  id: string;
  status: 'active' | 'closed';
  createdAt: string;
  updatedAt: string;
}

export interface AssistMessage {
  id: string;
  role: AssistRole;
  content: string;
  createdAt: string;
}

export interface AssistMessageRow {
  id: string;
  session_id: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  provider_reference: string | null;
  created_at: Date | string;
}

export interface AssistSessionRow {
  id: string;
  status: 'active' | 'closed';
  created_at: Date | string;
  updated_at: Date | string;
}

export function toAssistSession(row: AssistSessionRow): AssistSession {
  return {
    id: row.id,
    status: row.status,
    createdAt: toIso(row.created_at),
    updatedAt: toIso(row.updated_at)
  };
}

export function toAssistMessage(row: AssistMessageRow): AssistMessage {
  if (row.role !== 'user' && row.role !== 'assistant') throw new Error('Internal Assist messages cannot be exposed to clients');
  return { id: row.id, role: row.role, content: Array.from(row.content).slice(0, 4_000).join(''), createdAt: toIso(row.created_at) };
}

function toIso(value: Date | string): string {
  return value instanceof Date ? value.toISOString() : value;
}
