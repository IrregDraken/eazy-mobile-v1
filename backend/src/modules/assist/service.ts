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
  private readonly activeGenerations = new Map<string, AbortController>();

  constructor(
    private readonly pool: Pool,
    private readonly repository: AssistRepositoryContract,
    private readonly provider: AIProvider,
    private readonly tools: AssistToolRegistry
  ) {}

  async capabilities() {
    let providerAvailable = false;
    try { providerAvailable = this.provider.getCapabilities().available; } catch { /* report unavailable */ }
    return { providerAvailable, streaming: false, tools: await this.tools.list() };
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

  async cancelGeneration(userId: string, sessionId: string) {
    await this.requireSession(userId, sessionId);
    const controller = this.activeGenerations.get(this.generationKey(userId, sessionId));
    if (!controller || controller.signal.aborted) return { cancelled: false };
    controller.abort();
    return { cancelled: true };
  }

  async sendMessage(userId: string, sessionId: string, input: AssistMessageInput) {
    const session = await this.requireSession(userId, sessionId);
    const generationKey = this.generationKey(userId, sessionId);
    if (this.activeGenerations.has(generationKey)) throw new AppError('CONFLICT', 'An Assist response is already being generated');
    if (session.status !== 'active') throw new AppError('CONFLICT', 'Assist session is closed');

    const generationController = new AbortController();
    this.activeGenerations.set(generationKey, generationController);
    let userRow: Awaited<ReturnType<AssistRepositoryContract['insertMessage']>>;
    try {
      userRow = await withTransaction(this.pool, client =>
        this.repository.insertMessage(client, userId, sessionId, 'user', input.content)
      );
    } catch (error) {
      if (this.activeGenerations.get(generationKey) === generationController) {
        this.activeGenerations.delete(generationKey);
      }
      throw error;
    }
    if (!userRow) {
      if (this.activeGenerations.get(generationKey) === generationController) {
        this.activeGenerations.delete(generationKey);
      }
      throw new AppError('NOT_FOUND', 'Assist session not found');
    }

    if (isWalletBalanceIntent(input.content)) {
      try {
        if (generationController.signal.aborted) throw new AppError('CONFLICT', 'Assist generation cancelled');
        const toolResult = await this.tools.execute('get_wallet_balance', {}, userId);
        if (generationController.signal.aborted) throw new AppError('CONFLICT', 'Assist generation cancelled');
        if (toolResult.tool !== 'get_wallet_balance') {
          throw new AppError('INTERNAL_ERROR', 'Wallet balance capability returned an invalid result');
        }
        const content = formatWalletBalance(toolResult.wallet);
        const assistantRow = await withTransaction(this.pool, client =>
          this.repository.insertMessage(client, userId, sessionId, 'assistant', content)
        );
        if (!assistantRow) throw new AppError('NOT_FOUND', 'Assist session not found');
        return { userMessage: toAssistMessage(userRow), assistantMessage: toAssistMessage(assistantRow) };
      } catch (error) {
        if (!generationController.signal.aborted) throw error;
        const cancelledRow = await withTransaction(this.pool, client =>
          this.repository.insertMessage(client, userId, sessionId, 'assistant', 'Generation cancelled.')
        );
        if (!cancelledRow) throw new AppError('NOT_FOUND', 'Assist session not found');
        throw new AppError('CONFLICT', 'Assist generation cancelled');
      } finally {
        if (this.activeGenerations.get(generationKey) === generationController) {
          this.activeGenerations.delete(generationKey);
        }
      }
    }

    const abortController = generationController;
    try {
      const history = await this.repository.recentMessages(userId, sessionId, MAX_ASSIST_HISTORY_MESSAGES);
      const orderedHistory = [...history].reverse().filter(row => row.id !== userRow.id);
      const messages = await buildAssistMessages(orderedHistory, input.content, this.tools);
      const first = await this.complete(messages, abortController.signal);
      if (abortController.signal.aborted) throw new AppError('CONFLICT', 'Assist generation cancelled');
      if (Array.from(first.text).length > MAX_ASSIST_TOOL_CALL_CHARS) throw providerFailure();
      const allowedTools = (await this.tools.list()).map(tool => tool.name);
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
        if (abortController.signal.aborted) throw new AppError('CONFLICT', 'Assist generation cancelled');
        let toolMessages;
        try { toolMessages = buildAssistFollowupMessages(messages, first.text, toolResult); }
        catch { throw providerFailure(); }
        const second = await this.complete(toolMessages, abortController.signal);
        if (abortController.signal.aborted) throw new AppError('CONFLICT', 'Assist generation cancelled');
        const finalDecision = parseDecision(second.text, allowedTools);
        if (finalDecision.type !== 'answer') throw providerFailure();
        generated = finalDecision.text;
      }
      if (!generated.trim() || Array.from(generated).length > MAX_ASSIST_RESPONSE_CHARS) throw providerFailure();
      if (abortController.signal.aborted) throw new AppError('CONFLICT', 'Assist generation cancelled');
      const assistantRow = await withTransaction(this.pool, client => this.repository.insertMessage(client, userId, sessionId, 'assistant', generated));
      if (!assistantRow) throw new AppError('NOT_FOUND', 'Assist session not found');
      return { userMessage: toAssistMessage(userRow), assistantMessage: toAssistMessage(assistantRow) };
    } catch (error) {
      if (!abortController.signal.aborted) throw error;
      const cancelledRow = await withTransaction(this.pool, client => this.repository.insertMessage(client, userId, sessionId, 'assistant', 'Generation cancelled.'));
      if (!cancelledRow) throw new AppError('NOT_FOUND', 'Assist session not found');
      throw new AppError('CONFLICT', 'Assist generation cancelled');
    } finally {
      if (this.activeGenerations.get(generationKey) === abortController) this.activeGenerations.delete(generationKey);
    }
  }

  private generationKey(userId: string, sessionId: string) {
    return userId + ':' + sessionId;
  }

  private async complete(
    messages: Parameters<AIProvider['complete']>[0]['messages'],
    signal?: AbortSignal,
  ) {
    try {
      return await this.provider.complete({
        messages,
        jsonMode: true,
        maxOutputTokens: MAX_ASSIST_OUTPUT_TOKENS,
        signal,
      });
    } catch {
      if (signal?.aborted) throw new AppError('CONFLICT', 'Assist generation cancelled');
      throw providerFailure();
    }
  }

  private async requireSession(userId: string, sessionId: string) {
    const session = await this.repository.getSession(userId, sessionId);
    if (!session) throw new AppError('NOT_FOUND', 'Assist session not found');
    return session;
  }

}


function isWalletBalanceIntent(content: string): boolean {
  const normalized = content.toLowerCase();
  const asksForBalance = /\b(balance|available funds|wallet funds)\b/.test(normalized);
  const refersToAnotherPerson = /\b(their|his|her|someone else's|another user's)\b/.test(normalized);
  return asksForBalance && !refersToAnotherPerson;
}

function formatWalletBalance(wallet: { balance: string; currency: string; status: string } | null): string {
  if (!wallet) return "You do not have an active Eazy wallet yet.";
  if (wallet.status !== 'active') return "Your Eazy wallet is currently inactive, so I cannot show an available balance.";
  const [whole, fraction = '00'] = wallet.balance.split('.');
  const grouped = whole!.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const decimal = fraction.padEnd(2, '0').slice(0, 2);
  const amount = wallet.currency === 'NGN'
    ? '₦' + grouped + '.' + decimal
    : wallet.currency + ' ' + grouped + '.' + decimal;
  return 'Your Eazy wallet balance is ' + amount + '.';
}
