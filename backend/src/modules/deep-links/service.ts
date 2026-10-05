import type { Pool } from 'pg';
import { z } from 'zod';
import { AppError } from '../../middleware/errors.js';
import type { ChatService } from '../chat/service.js';
import type { MarketplaceService } from '../marketplace/service.js';
import type { NotificationService } from '../notifications/service.js';
import type { OrderService } from '../orders/service.js';
import type { PostService } from '../posts/service.js';
import type { ProfileService } from '../profiles/service.js';
import { usernameSchema } from '../profiles/service.js';
import { SocialRepository } from '../social/repository.js';

const resourceIdSchema = z.string().uuid();
const canonicalHost = 'eazy.app';

export interface DeepLinkServices {
  profiles: Pick<ProfileService, 'getPublic'>;
  posts: Pick<PostService, 'getById'>;
  marketplace: Pick<MarketplaceService, 'detail'>;
  orders: Pick<OrderService, 'get'>;
  notifications: Pick<NotificationService, 'get'>;
  chat: Pick<ChatService, 'getConversation'>;
}

export type DeepLinkTarget =
  | { type: 'profile'; identifier: string; destination: string }
  | { type: 'post' | 'product' | 'order' | 'notification' | 'conversation'; id: string; destination: string };

type ParsedDeepLink =
  | { type: 'profile'; identifier: string }
  | { type: 'post' | 'product' | 'order' | 'notification' | 'conversation'; id: string };

export class DeepLinkService {
  constructor(
    private readonly services: DeepLinkServices,
    private readonly pool: Pool,
    private readonly social = new SocialRepository(pool)
  ) {}

  async resolve(input: string, viewerId?: string): Promise<DeepLinkTarget> {
    const parsed = parseDeepLink(input);
    switch (parsed.type) {
      case 'profile': {
        const target = await this.social.targetByUsername(this.pool, parsed.identifier);
        if (!target) throw new AppError('NOT_FOUND', 'Deep link target is unavailable');
        if (viewerId && await this.social.isBlocked(this.pool, viewerId, target.id)) {
          throw new AppError('NOT_FOUND', 'Deep link target is unavailable');
        }
        await this.services.profiles.getPublic(parsed.identifier, viewerId);
        return { type: 'profile', identifier: parsed.identifier, destination: `/u/${parsed.identifier}` };
      }
      case 'post': {
        await this.services.posts.getById(parsed.id, viewerId);
        return { type: 'post', id: parsed.id, destination: `/p/${parsed.id}` };
      }
      case 'product': {
        await this.services.marketplace.detail(parsed.id, viewerId);
        return { type: 'product', id: parsed.id, destination: `/product/${parsed.id}` };
      }
      case 'order': {
        const userId = requireViewer(viewerId);
        await this.services.orders.get(userId, parsed.id);
        return { type: 'order', id: parsed.id, destination: `/order/${parsed.id}` };
      }
      case 'notification': {
        const userId = requireViewer(viewerId);
        await this.services.notifications.get(userId, parsed.id);
        return { type: 'notification', id: parsed.id, destination: `/notification/${parsed.id}` };
      }
      case 'conversation': {
        const userId = requireViewer(viewerId);
        await this.services.chat.getConversation(userId, parsed.id);
        return { type: 'conversation', id: parsed.id, destination: `/chat/${parsed.id}` };
      }
    }
  }
}

export function parseDeepLink(input: string): ParsedDeepLink {
  if (!input || input.length > 2048 || input.includes('?') || input.includes('#') || input.includes('\\')) {
    throw new AppError('VALIDATION_ERROR', 'Invalid deep link');
  }

  let path = input;
  const absolute = input.match(/^([a-z][a-z0-9+.-]*):\/\/([^/?#]*)(.*)$/i);
  if (absolute) {
    if (absolute[1]?.toLowerCase() !== 'https' || absolute[2]?.toLowerCase() !== canonicalHost) {
      throw new AppError('VALIDATION_ERROR', 'Unsupported deep-link scheme or host');
    }
    path = absolute[3] || '/';
  } else if (/^[a-z][a-z0-9+.-]*:/i.test(input) || input.startsWith('//')) {
    throw new AppError('VALIDATION_ERROR', 'Unsupported deep-link scheme or host');
  }

  if (!path.startsWith('/') || path.startsWith('//')) throw new AppError('VALIDATION_ERROR', 'Invalid deep-link path');
  if (/%(?:2f|5c)/i.test(path)) throw new AppError('VALIDATION_ERROR', 'Encoded path separators are not allowed');

  const segments: string[] = [];
  for (const rawSegment of path.split('/').filter(Boolean)) {
    let segment: string;
    try { segment = decodeURIComponent(rawSegment); }
    catch { throw new AppError('VALIDATION_ERROR', 'Invalid URL encoding in deep link'); }
    if (!segment || segment === '.' || segment === '..' || segment.includes('/') || segment.includes('\\')) {
      throw new AppError('VALIDATION_ERROR', 'Invalid deep-link path segment');
    }
    segments.push(segment);
  }

  if (segments.length !== 2) throw new AppError('NOT_FOUND', 'Deep-link route not found');
  const [kind, rawIdentifier] = segments as [string, string];
  if (kind === 'u') {
    const result = usernameSchema.safeParse(rawIdentifier);
    if (!result.success) throw new AppError('VALIDATION_ERROR', 'Invalid profile identifier');
    return { type: 'profile', identifier: result.data };
  }

  const resourceTypes: Record<string, 'post' | 'product' | 'order' | 'notification' | 'conversation'> = {
    p: 'post', product: 'product', order: 'order', notification: 'notification', chat: 'conversation'
  };
  const type = resourceTypes[kind];
  if (!type) throw new AppError('NOT_FOUND', 'Deep-link route not found');
  const parsedId = resourceIdSchema.safeParse(rawIdentifier);
  if (!parsedId.success) throw new AppError('VALIDATION_ERROR', 'Invalid resource identifier');
  return { type, id: parsedId.data.toLowerCase() };
}

function requireViewer(viewerId?: string): string {
  if (!viewerId) throw new AppError('UNAUTHORIZED', 'Authentication required');
  return viewerId;
}
