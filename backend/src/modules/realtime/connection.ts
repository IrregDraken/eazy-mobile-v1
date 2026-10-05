import type { IncomingMessage, Server as HttpServer } from 'node:http';
import type { Socket } from 'node:net';
import WebSocket, { WebSocketServer } from 'ws';
import type { AppConfig } from '../../config/env.js';
import type { FirebaseAuthProvider } from '../../providers/firebase-auth.js';
import type { AuthService } from '../auth/service.js';
import { FixedWindowRateLimiter } from '../../middleware/rate-limit.js';
import { clientFrameError, getClientErrorCode, normalizeChannel, originAllowed, parseBearerToken, parseClientMessage, pathIsRealtime, REALTIME_LIMITS, safeError } from './events.js';
import type { RealtimeConnection } from './dispatcher.js';
import { RealtimeService } from './service.js';
import type { Logger } from 'pino';

export interface RealtimeGateway {
  close(): Promise<void>;
}

export function attachRealtimeGateway(server: HttpServer, config: AppConfig, provider: FirebaseAuthProvider, auth: AuthService, realtime: RealtimeService, logger?: Logger): RealtimeGateway {
  const websocketServer = new WebSocketServer({ noServer: true, maxPayload: REALTIME_LIMITS.maxFrameBytes, perMessageDeflate: false, clientTracking: false });
  const attempts = new FixedWindowRateLimiter();
  const windowMs = Math.max(config.RATE_LIMIT_WINDOW_MS, REALTIME_LIMITS.operationWindowMs);
  const connectionLimit = Math.min(Math.max(1, config.RATE_LIMIT_MAX), 100);
  realtime.startHeartbeat();

  const onUpgrade = (request: IncomingMessage, socket: Socket, head: Buffer) => {
    const pathname = request.url ?? '';
    if (!pathIsRealtime(pathname)) return reject(socket, 404, 'Not Found');
    const address = request.socket.remoteAddress ?? 'unknown';
    const attempt = attempts.consume(`realtime:connect:${address}`, connectionLimit, windowMs);
    if (!attempt.allowed) return reject(socket, 429, 'Too Many Requests');
    if (!originAllowed(request.headers.origin, config.CORS_ORIGIN)) return reject(socket, 403, 'Forbidden');
    const token = parseBearerToken(request.headers.authorization);
    if (!token) return reject(socket, 401, 'Unauthorized');

    void (async () => {
      try {
        const identity = await provider.verifyIdentity(token);
        const result = await auth.provision(identity, {
          ipAddress: request.socket.remoteAddress,
          userAgent: request.headers['user-agent']
        });
        if (result.record.user.status !== 'active') {
          reject(socket, 403, 'Forbidden');
          return;
        }
        if (realtime.dispatcher.getConnectionCountForUser(result.context.userId) >= REALTIME_LIMITS.maxConnectionsPerUser) {
          reject(socket, 429, 'Too Many Requests');
          return;
        }
        if (!pathIsRealtime(request.url) || socket.destroyed) return;
        websocketServer.handleUpgrade(request, socket, head, ws => {
          const connection = realtime.register(ws, result.context.userId, result.context.sessionId);
          if (!connection) {
            ws.close(4429, 'Connection limit exceeded');
            return;
          }
          logger?.info({ event: 'realtime.connection.accepted', userId: connection.userId, sessionId: connection.sessionId }, 'realtime connection accepted');
          websocketServer.emit('connection', ws, request, connection);
        });
      } catch (error) {
        logger?.warn({ event: 'realtime.connection.rejected', reason: getClientErrorCode(error) }, 'realtime connection rejected');
        const code = getClientErrorCode(error);
        if (code === 'internal_error') return reject(socket, 503, 'Service Unavailable');
        reject(socket, code === 'rate_limited' ? 429 : code === 'forbidden' ? 403 : 401, code === 'rate_limited' ? 'Too Many Requests' : code === 'forbidden' ? 'Forbidden' : 'Unauthorized');
      }
    })();
  };

  server.on('upgrade', onUpgrade);

  websocketServer.on('error', () => { /* transport failures are handled per connection and must not crash the process */ });
  websocketServer.on('connection', (socket: WebSocket, _request: IncomingMessage, connection: RealtimeConnection) => {
    socket.on('pong', () => { connection.lastPongAt = Date.now(); connection.isAlive = true; });
    socket.on('message', (data, isBinary) => {
      if (connection.closed) return;
      const rate = consumeConnectionWindow(connection, 'frames');
      if (!rate.allowed) {
        safeSend(socket, safeError('rate_limited'));
        socket.close(4429, 'Realtime rate limit exceeded');
        return;
      }
      if (isBinary) {
        malformed(connection, socket);
        return;
      }
      const raw = data.toString();
      if (Buffer.byteLength(raw, 'utf8') > REALTIME_LIMITS.maxFrameBytes) {
        socket.close(1009, 'Message too large');
        return;
      }
      const message = parseClientMessage(raw);
      if (!message) {
        malformed(connection, socket, clientFrameError(raw));
        return;
      }
      const subRate = consumeConnectionWindow(connection, 'subscriptions');
      if (!subRate.allowed) {
        safeSend(socket, safeError('rate_limited'));
        socket.close(4429, 'Realtime rate limit exceeded');
        return;
      }
      const channel = normalizeChannel(message.channel, message.id);
      if (message.type === 'unsubscribe') {
        realtime.dispatcher.unsubscribe(connection, channel);
        safeSend(socket, { type: 'unsubscribed', channel: message.channel, id: message.id.toLowerCase() });
        return;
      }
      const sequence = realtime.dispatcher.beginSubscriptionOperation(connection, channel);
      void (async () => {
        const allowed = await realtime.authorizeChannel(connection.userId, message.channel, message.id);
        if (!realtime.dispatcher.isLatestSubscriptionOperation(connection, channel, sequence)) return;
        if (!allowed) {
          realtime.dispatcher.finishSubscriptionOperation(connection, channel, sequence);
          safeSend(socket, safeError(message.channel === 'user' ? 'forbidden' : 'not_found'));
          return;
        }
        if (!realtime.dispatcher.subscribe(connection, channel, REALTIME_LIMITS.maxSubscriptionsPerConnection)) {
          realtime.dispatcher.finishSubscriptionOperation(connection, channel, sequence);
          safeSend(socket, safeError('rate_limited'));
          return;
        }
        realtime.dispatcher.finishSubscriptionOperation(connection, channel, sequence);
        safeSend(socket, { type: 'subscribed', channel: message.channel, id: message.id.toLowerCase() });
      })().catch(() => {
        if (!realtime.dispatcher.isLatestSubscriptionOperation(connection, channel, sequence)) return;
        realtime.dispatcher.finishSubscriptionOperation(connection, channel, sequence);
        safeSend(socket, safeError('internal_error'));
      });
    });
    socket.once('close', (code, reason) => {
      logger?.info({ event: 'realtime.connection.closed', userId: connection.userId, sessionId: connection.sessionId, code, reason: reason.toString().slice(0, 128) }, 'realtime connection closed');
      realtime.dispatcher.remove(connection);
    });
    socket.once('error', () => {
      logger?.warn({ event: 'realtime.connection.error', userId: connection.userId, sessionId: connection.sessionId }, 'realtime connection error');
      realtime.dispatcher.remove(connection);
    });
    safeSend(socket, { type: 'ready', userId: connection.userId });
  });

  return {
    async close() {
      server.off('upgrade', onUpgrade);
      await realtime.close();
      await new Promise<void>(resolve => websocketServer.close(() => resolve()));
    }
  };
}

function consumeConnectionWindow(connection: RealtimeConnection, kind: 'frames' | 'subscriptions') {
  const now = Date.now();
  const frameWindow = kind === 'frames';
  const startedAt = frameWindow ? connection.frameWindowStartedAt : connection.subscriptionWindowStartedAt;
  let count = frameWindow ? connection.framesInWindow : connection.subscriptionsInWindow;
  if (now - startedAt >= REALTIME_LIMITS.operationWindowMs) {
    count = 0;
    if (frameWindow) connection.frameWindowStartedAt = now;
    else connection.subscriptionWindowStartedAt = now;
  }
  count += 1;
  if (frameWindow) connection.framesInWindow = count;
  else connection.subscriptionsInWindow = count;
  const max = frameWindow ? REALTIME_LIMITS.framesPerWindow : REALTIME_LIMITS.subscriptionsPerWindow;
  return { allowed: count <= max, remaining: Math.max(0, max - count) };
}

function malformed(connection: RealtimeConnection, socket: WebSocket, code: 'invalid_message' | 'invalid_subscription' = 'invalid_message') {
  connection.malformedFrames += 1;
  safeSend(socket, safeError(code));
  if (connection.malformedFrames >= REALTIME_LIMITS.malformedFramesBeforeClose) socket.close(1008, 'Invalid realtime messages');
}

function safeSend(socket: WebSocket, value: unknown) {
  if (socket.readyState !== WebSocket.OPEN) return;
  try { socket.send(JSON.stringify(value)); } catch { socket.terminate(); }
}

function reject(socket: Socket, status: number, label: string) {
  if (socket.destroyed) return;
  const body = `HTTP/1.1 ${status} ${label}\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`;
  socket.end(body);
}
