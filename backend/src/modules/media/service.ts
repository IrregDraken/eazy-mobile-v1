import { randomUUID } from 'node:crypto';
import { AppError } from '../../middleware/errors.js';
import type { SupabaseStorageProvider } from '../../providers/supabase-storage.js';

const allowedTypes = new Set(['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','audio/mpeg','audio/mp4','audio/wav']);

export class MediaService {
  constructor(private readonly storage: SupabaseStorageProvider) {}

  capabilities() { return this.storage.getCapabilities(); }

  async createUpload(userId: string, input: { contentType: string; extension?: string; kind: 'avatar'|'post'|'message'|'product' }) {
    if (!allowedTypes.has(input.contentType)) throw new AppError('BAD_REQUEST', 'Unsupported media type');
    const extension = (input.extension || input.contentType.split('/')[1] || 'bin').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 8) || 'bin';
    const key = userId + '/' + input.kind + '/' + new Date().toISOString().slice(0,10) + '/' + randomUUID() + '.' + extension;
    try {
      return await this.storage.createSignedUploadUrl(key, false);
    } catch {
      throw new AppError('SERVICE_UNAVAILABLE', 'Media storage is not configured');
    }
  }

  async signRead(userId: string, path: string) {
    if (!path.startsWith(userId + '/')) throw new AppError('FORBIDDEN', 'You can only sign your own private media');
    if (path.includes('..') || path.startsWith('/') || path.length > 1024) throw new AppError('BAD_REQUEST', 'Invalid media path');
    try { return await this.storage.createSignedUrl(path, 3600); }
    catch { throw new AppError('NOT_FOUND', 'Media could not be signed'); }
  }
}