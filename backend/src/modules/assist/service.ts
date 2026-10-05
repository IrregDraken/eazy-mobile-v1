import { withTransaction } from '../../database/client.js';
import type { Pool } from 'pg';
import { AppError } from '../../middleware/errors.js';
import type { AIProvider } from '../../providers/interfaces.js';
import { paginationMeta } from '../../utils/pagination.js';
import { buildAssistFollowupMessages, buildAssistMessages, MAX_ASSIST_HISTORY_MESSAGES, MAX_ASSIST_OUTPUT_TOKENS, MAX_ASSIST_TOOL_CALL_CHARS } from './context.js';
import type { AssistRepositoryContract } from './repository.js';
import { AssistToolRegistry } from './tools/registry.js';
import type { AssistHistoryQuery, AssistMessageInput } from './schemas.js';
import { toAssistMessage, toAssistSession } from './types.js';
import { parseDecision, providerFailure, MAX_ASSIST_RESPONSE_CHARS } from './validation.js';

export class AssistService {
  constructor(
    private readonly pool: Pool,
    private readonly repository: AssistRepositoryContract,
    private readonly provider: AIProvider,
    private readonly tools: AssistToolRegistry
  ) {}

  capabilities() {
    let providerAvailable = false;
    try { providerAvailable = this.provider.getCapabilities().available; } catch { /* report unavailable */ }
    return { providerAvailable, streaming: false, tools: this.tools.list() };
  }

  async createSession(userId: string) {
    return { session: toAssistSession(await this.repository.createSession(userId)) };
  }

  async listSessions(userId: string, query: AssistHistoryQuery) {
    const result = await this.repository.listSessions(userId, query.page, query.limit);
    return { items: result.items.map(toAssistSession), meta: paginationMeta(query, result.total) };
  }

  async getSession(userId: string, sessionId: string) {
    const session = await this.requireSession(userId, sessionId);
    return { session: toAssistSession(session) };
  }

  async closeSession(userId: string, sessionId: string) {
    const session = await this.repository.closeSession(userId, sessionId);
    if (!session) throw new AppError('NOT_FOUND', 'Assist session not found');
    return { session: toAssistSession(session) };
  }

  async listMessages(userId: string, sessionId: string, query: AssistHistoryQuery) {
    const session = await this.requireSession(userId, sessionId);
    const result = await this.repository.listMessages(userId, sessionId, query.page, query.limit);
    return {
      session: toAssistSession(session),
      items: result.items.map(toAssistMessage),
      meta: paginationMeta(query, result.total)
    };
  }

  async sendMessage(userId: string, sessionId: string, input: AssistMessageInput) {
    const session = await this.requireSession(userId, sessionId);
    if (session.status !== 'active') throw new AppError('CONFLICT', 'Assist session is closed');

    const userRow = await withTransaction(this.pool, client => this.repository.insertMessage(client, userId, sessionId, 'user', input.content));
    if (!userRow) throw new AppError('NOT_FOUND', 'Assist session not found');
    const history = await this.repository.recentMessages(userId, sessionId, MAX_ASSIST_HISTORY_MESSAGES);
    const orderedHistory = [...history].reverse().filter(row => row.id !== userRow.id);
    const messages = buildAssistMessages(orderedHistory, input.content, this.tools);

    const first = await this.complete(messages);
    if (Array.from(first.text).length > MAX_ASSIST_TOOL_CALL_CHARS) throw providerFailure();
    const allowedTools = this.tools.list().map(tool => tool.name);
    const decision = parseDecision(first.text, allowedTools);
    let generated: string;
    if (decision.type === 'answer') {
      generated = decision.text;
    } else {
      let toolResult;
      try { toolResult = await this.tools.execute(decision.name, decision.arguments, userId); }
      catch (error) {
        if (error instanceof AppError && (error.code === 'VALIDATION_ERROR' || error.code === 'BAD_REQUEST')) throw providerFailure();
        if (error instanceof AppError) throw error;
        throw new AppError('INTERNAL_ERROR', 'Assist capability failed');
      }
      let toolMessages;
      try { toolMessages = buildAssistFollowupMessages(messages, first.text, toolResult); }
      catch { throw providerFailure(); }
      const second = await this.complete(toolMessages);
      const finalDecision = parseDecision(second.text, allowedTools);
      if (finalDecision.type !== 'answer') throw providerFailure();
      generated = finalDecision.text;
    }

    if (!generated.trim() || Array.from(generated).length > MAX_ASSIST_RESPONSE_CHARS) throw providerFailure();
    const assistantRow = await withTransaction(this.pool, client => this.repository.insertMessage(client, userId, sessionId, 'assistant', generated));
    if (!assistantRow) throw new AppError('NOT_FOUND', 'Assist session not found');
    return { userMessage: toAssistMessage(userRow), assistantMessage: toAssistMessage(assistantRow) };
  }

  private async complete(messages: Parameters<AIProvider['complete']>[0]['messages']) {
    try { return await this.provider.complete({ messages, jsonMode: true, maxOutputTokens: MAX_ASSIST_OUTPUT_TOKENS }); }
    catch { throw providerFailure(); }
  }

  private async requireSession(userId: string, sessionId: string) {
    const session = await this.repository.getSession(userId, sessionId);
    if (!session) throw new AppError('NOT_FOUND', 'Assist session not found');
    return session;
  }

}
