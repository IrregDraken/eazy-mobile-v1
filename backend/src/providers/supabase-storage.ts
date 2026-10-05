import type { AppConfig } from '../config/env.js';

export class SupabaseStorageProvider {
  private readonly baseUrl: string;
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
  private encodePath(path: string) { return path.split('/').filter(Boolean).map(segment => encodeURIComponent(segment)).join('/'); }
  private async request(path: string, init: RequestInit = {}) {
    const response = await fetch(this.baseUrl + path, { ...init, headers: { authorization: 'Bearer ' + this.config.SUPABASE_SERVICE_ROLE_KEY, apikey: this.config.SUPABASE_SERVICE_ROLE_KEY!, 'content-type': 'application/json', ...(init.headers ?? {}) } });
    const body = await response.json() as any;
    if (!response.ok) throw new Error(String(body?.message ?? body?.error ?? 'Storage provider request failed'));
    return body;
  }
  private assertConfigured() { if (!this.config.SUPABASE_URL || !this.config.SUPABASE_SERVICE_ROLE_KEY) throw new Error('Supabase storage is not configured'); }
}