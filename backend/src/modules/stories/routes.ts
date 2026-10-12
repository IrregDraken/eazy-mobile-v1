import { Router } from 'express';
import { z } from 'zod';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { requireAuth, currentUserId } from '../../middleware/auth.js';
import { validate } from '../../middleware/validate.js';
import { AppError } from '../../middleware/errors.js';
import { sendSuccess } from '../../utils/http.js';
import type { SupabaseStorageProvider } from '../../providers/supabase-storage.js';

const createStorySchema = z.object({
  storageKey: z.string().trim().min(1).max(1024),
  mediaType: z.enum(['image', 'video']).default('image'),
  caption: z.string().trim().max(500).default('')
}).strict();
const storyIdSchema = z.object({ storyId: z.string().uuid() });
const highlightIdSchema = z.object({ highlightId: z.string().uuid() });
const createHighlightSchema = z.object({ title: z.string().trim().min(1).max(40), storyIds: z.array(z.string().uuid()).min(1).max(100) }).strict();
const usernameSchema = z.object({ username: z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,32}$/) });

export class StoryService {
  constructor(private readonly pool: Pool, private readonly storage?: SupabaseStorageProvider) {}

  async feed(viewerId: string) {
    const result = await this.pool.query<{
      id: string; authorId: string; username: string; displayName: string;
      avatarUrl: string | null; storageKey: string; mediaType: 'image' | 'video';
      caption: string; createdAt: string; expiresAt: string; seenByMe: boolean;
      isMine: boolean;
    }>(`SELECT s.id, s.author_id AS "authorId", p.username, p.display_name AS "displayName",
      p.avatar_url AS "avatarUrl", s.storage_key AS "storageKey", s.media_type AS "mediaType",
      s.caption, s.created_at AS "createdAt", s.expires_at AS "expiresAt",
      EXISTS(SELECT 1 FROM story_views sv WHERE sv.story_id=s.id AND sv.viewer_id=$1) AS "seenByMe",
      (s.author_id=$1) AS "isMine"
      FROM stories s JOIN profiles p ON p.user_id=s.author_id
      WHERE s.expires_at > now()
        AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=s.author_id) OR (b.blocker_id=s.author_id AND b.blocked_id=$1))
        AND (s.author_id=$1 OR EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.followee_id=s.author_id))
      ORDER BY (s.author_id=$1) DESC, s.created_at DESC
      LIMIT 250`, [viewerId]);
    return { items: await Promise.all(result.rows.map(row => this.present(row))) };
  }

  async create(authorId: string, input: z.infer<typeof createStorySchema>) {
    if (!this.storage) throw new AppError('SERVICE_UNAVAILABLE', 'Media storage is not configured');
    // Eazy upload keys are scoped to the authenticated user by MediaService.
    if (!input.storageKey.startsWith(authorId + '/') || input.storageKey.includes('..') || input.storageKey.startsWith('/')) {
      throw new AppError('VALIDATION_ERROR', 'Choose media uploaded to your Eazy account');
    }
    const inserted = await this.pool.query<{ id: string }>(
      'INSERT INTO stories (author_id, storage_key, media_type, caption) VALUES ($1,$2,$3,$4) RETURNING id',
      [authorId, input.storageKey, input.mediaType, input.caption]
    );
    const row = await this.pool.query('SELECT s.id, s.author_id AS "authorId", p.username, p.display_name AS "displayName", p.avatar_url AS "avatarUrl", s.storage_key AS "storageKey", s.media_type AS "mediaType", s.caption, s.created_at AS "createdAt", s.expires_at AS "expiresAt", false AS "seenByMe", true AS "isMine" FROM stories s JOIN profiles p ON p.user_id=s.author_id WHERE s.id=$1', [inserted.rows[0]!.id]);
    return { story: await this.present(row.rows[0]) };
  }

  async markSeen(storyId: string, viewerId: string) {
    const accessible = await this.pool.query(`SELECT s.id FROM stories s
      WHERE s.id=$1 AND s.expires_at>now()
      AND NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id=$2 AND b.blocked_id=s.author_id) OR (b.blocker_id=s.author_id AND b.blocked_id=$2))
      AND (s.author_id=$2 OR EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$2 AND f.followee_id=s.author_id))`, [storyId, viewerId]);
    if (!accessible.rowCount) throw new AppError('NOT_FOUND', 'Story not found');
    await this.pool.query('INSERT INTO story_views (story_id, viewer_id) VALUES ($1,$2) ON CONFLICT (story_id,viewer_id) DO UPDATE SET viewed_at=now()', [storyId, viewerId]);
    return { seen: true };
  }

  async listHighlights(username: string) {
    const result = await this.pool.query<any>(`SELECT h.id, h.title, h.cover_storage_key AS "coverStorageKey",
      h.created_at AS "createdAt", p.username, p.display_name AS "displayName", p.avatar_url AS "avatarUrl",
      COALESCE((SELECT json_agg(json_build_object('id',s.id,'storageKey',s.storage_key,'mediaType',s.media_type,'caption',s.caption,'createdAt',s.created_at,'position',hs.position) ORDER BY hs.position, hs.created_at)
        FROM profile_highlight_stories hs JOIN stories s ON s.id=hs.story_id WHERE hs.highlight_id=h.id), '[]'::json) AS stories
      FROM profile_highlights h JOIN profiles p ON p.user_id=h.owner_id
      WHERE p.username=$1 ORDER BY h.created_at ASC`, [username.toLowerCase()]);
    return { items: await Promise.all(result.rows.map(async row => {
      const stories = await Promise.all((row.stories as any[]).map(async story => {
        let mediaUrl: string | null = null;
        if (this.storage) { try { mediaUrl = (await this.storage.createSignedUrl(story.storageKey, 3600)).signedUrl; } catch { mediaUrl = null; } }
        return { ...story, mediaUrl };
      }));
      let coverUrl: string | null = null;
      if (this.storage && row.coverStorageKey) { try { coverUrl = (await this.storage.createSignedUrl(row.coverStorageKey, 3600)).signedUrl; } catch { coverUrl = null; } }
      return { ...row, coverUrl, stories };
    }) };
  }

  async createHighlight(ownerId: string, input: z.infer<typeof createHighlightSchema>) {
    if (!this.storage) throw new AppError('SERVICE_UNAVAILABLE', 'Media storage is not configured');
    const uniqueIds = [...new Set(input.storyIds)];
    const result = await withTransaction(this.pool, async client => {
      const found = await client.query<{ id: string; storage_key: string }>(
        'SELECT id, storage_key FROM stories WHERE author_id=$1 AND id=ANY($2::uuid[]) ORDER BY created_at ASC',
        [ownerId, uniqueIds]
      );
      if (found.rows.length !== uniqueIds.length) throw new AppError('VALIDATION_ERROR', 'Highlights can only include your own stories');
      const created = await client.query<{ id: string }>(
        'INSERT INTO profile_highlights (owner_id,title,cover_storage_key) VALUES ($1,$2,$3) RETURNING id',
        [ownerId, input.title, found.rows[0]!.storage_key]
      );
      for (let i=0; i<found.rows.length; i++) {
        await client.query('INSERT INTO profile_highlight_stories (highlight_id,story_id,position) VALUES ($1,$2,$3)', [created.rows[0]!.id, found.rows[i]!.id, i]);
      }
      return created.rows[0]!.id;
    });
    return { highlightId: result };
  }

  async deleteHighlight(highlightId: string, ownerId: string) {
    const result = await this.pool.query('DELETE FROM profile_highlights WHERE id=$1 AND owner_id=$2 RETURNING id', [highlightId, ownerId]);
    if (!result.rowCount) throw new AppError('NOT_FOUND', 'Highlight not found');
    return { deleted: true };
  }

  async delete(storyId: string, authorId: string) {
    const result = await this.pool.query('DELETE FROM stories WHERE id=$1 AND author_id=$2 RETURNING id', [storyId, authorId]);
    if (!result.rowCount) throw new AppError('NOT_FOUND', 'Story not found');
    return { deleted: true };
  }

  private async present(row: any) {
    let mediaUrl: string | null = null;
    if (this.storage && row.storageKey) {
      try { mediaUrl = (await this.storage.createSignedUrl(row.storageKey, 3600)).signedUrl; } catch { mediaUrl = null; }
    }
    return { ...row, mediaUrl };
  }
}

export function createStoryRouter(service: StoryService): Router {
  const router = Router();
  router.get('/feed', requireAuth, async (request, response) => sendSuccess(response, await service.feed(currentUserId(request))));
  router.post('/', requireAuth, validate('body', createStorySchema), async (request, response) => response.status(201).json({ success: true, data: await service.create(currentUserId(request), request.body), meta: {} }));
  router.post('/:storyId/view', requireAuth, validate('params', storyIdSchema), async (request, response) => sendSuccess(response, await service.markSeen(param(request.params.storyId), currentUserId(request))));
  router.delete('/:storyId', requireAuth, validate('params', storyIdSchema), async (request, response) => sendSuccess(response, await service.delete(param(request.params.storyId), currentUserId(request))));
  router.get('/highlights/:username', validate('params', usernameSchema), async (request, response) => sendSuccess(response, await service.listHighlights(param(request.params.username))));
  router.post('/highlights', requireAuth, validate('body', createHighlightSchema), async (request, response) => response.status(201).json({ success: true, data: await service.createHighlight(currentUserId(request), request.body), meta: {} }));
  router.delete('/highlights/:highlightId', requireAuth, validate('params', highlightIdSchema), async (request, response) => sendSuccess(response, await service.deleteHighlight(param(request.params.highlightId), currentUserId(request))));
  return router;
}

function param(value: string | string[] | undefined): string { return typeof value === 'string' ? value : ''; }
