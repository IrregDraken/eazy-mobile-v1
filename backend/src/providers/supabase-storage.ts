import type { AppConfig } from '../config/env.js';

export interface StorageCleanupResult {
  deleted: number;
  requested: number;
}

export class SupabaseStorageProvider {
  private readonly baseUrl: string;
  private static readonly deleteBatchSize = 100;
  private static readonly maxAttempts = 3;
  constructor(private readonly config: AppConfig) {
    if (!config.SUPABASE_URL || !config.SUPABASE_SERVICE_ROLE_KEY) throw new Error('Supabase storage is not configured');
    this.baseUrl = config.SUPABASE_URL.replace(/\/$/, '');
  }
  getCapabilities() { return { available: Boolean(this.config.SUPABASE_URL && this.config.SUPABASE_SERVICE_ROLE_KEY), bucket: this.config.MEDIA_BUCKET }; }
  async createSignedUploadUrl(path: string, upsert = false) {
    this.assertConfigured();
    const response = await this.request('/storage/v1/object/upload/sign/' + this.config.MEDIA_BUCKET + '/' + this.encodePath(path), { method: 'POST', headers: upsert ? { 'x-upsert': 'true' } : undefined });
    const signedPath = String(response.url ?? '');
    const token = new URL(this.baseUrl + signedPath).searchParams.get('token');
    if (!token) throw new Error('Storage provider did not return an upload token');
    return { path, token, signedUrl: signedPath.startsWith('http') ? signedPath : this.baseUrl + '/storage/v1' + signedPath };
  }
  async createSignedUrl(path: string, expiresInSeconds = 3600) {
    this.assertConfigured();
    const response = await this.request('/storage/v1/object/sign/' + this.config.MEDIA_BUCKET + '/' + this.encodePath(path), { method: 'POST', body: JSON.stringify({ expiresIn: expiresInSeconds }) });
    const signedPath = String(response.signedURL ?? response.signedUrl ?? '');
    if (!signedPath) throw new Error('Storage provider did not return a signed URL');
    return { path, signedUrl: signedPath.startsWith('http') ? signedPath : this.baseUrl + '/storage/v1' + signedPath };
  }
  /** Deletes exact, server-verified keys only. Supabase treats absent objects as idempotent. */
  async deleteObjects(paths: readonly string[]): Promise<StorageCleanupResult> {
    this.assertConfigured();
    const safePaths = [...new Set(paths)].filter(path => path.length > 0 && !path.startsWith('/') && !path.includes('..') && !path.includes('\\'));
    if (safePaths.length !== paths.length) throw new Error('Storage cleanup received an invalid object path');
    let deleted = 0;
    for (let offset = 0; offset < safePaths.length; offset += SupabaseStorageProvider.deleteBatchSize) {
      const batch = safePaths.slice(offset, offset + SupabaseStorageProvider.deleteBatchSize);
      await this.withRetry(() => this.request('/storage/v1/object/remove/' + this.config.MEDIA_BUCKET, {
        method: 'POST', body: JSON.stringify({ prefixes: batch })
      }));
      deleted += batch.length;
    }
    return { deleted, requested: safePaths.length };
  }
  private async withRetry<T>(operation: () => Promise<T>): Promise<T> {
    let lastError: unknown;
    for (let attempt = 1; attempt <= SupabaseStorageProvider.maxAttempts; attempt += 1) {
      try { return await operation(); } catch (error) {
        lastError = error;
        if (attempt < SupabaseStorageProvider.maxAttempts) await new Promise(resolve => setTimeout(resolve, 25 * 2 ** (attempt - 1)));
      }
    }
    throw lastError instanceof Error ? lastError : new Error('Storage cleanup failed');
  }
  private encodePath(path: string) { return path.split('/').filter(Boolean).map(segment => encodeURIComponent(segment)).join('/'); }
  private async request(path: string, init: RequestInit = {}) {
    const response = await fetch(this.baseUrl + path, { ...init, headers: { authorization: 'Bearer ' + this.config.SUPABASE_SERVICE_ROLE_KEY, apikey: this.config.SUPABASE_SERVICE_ROLE_KEY!, 'content-type': 'application/json', ...(init.headers ?? {}) } });
    const text = await response.text();
    let body: any = {};
    try { body = text ? JSON.parse(text) : {}; } catch { /* provider may return an empty body */ }
    if (!response.ok) throw new Error(String(body?.message ?? body?.error ?? 'Storage provider request failed'));
    return body;
  }
  private assertConfigured() { if (!this.config.SUPABASE_URL || !this.config.SUPABASE_SERVICE_ROLE_KEY) throw new Error('Supabase storage is not configured'); }
}
