import { z } from 'zod';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { Pool } from 'pg';
import { ProfileRepository, type ProfileRecord } from './repository.js';
import type { SupabaseStorageProvider } from '../../providers/supabase-storage.js';

const usernamePattern = /^[a-z0-9_]{3,32}$/;
export const usernameSchema = z.string().trim().toLowerCase().regex(usernamePattern, 'Username must be 3-32 lowercase letters, numbers, or underscores');

const optionalNameSchema = z.preprocess(value => typeof value === 'string' && value.trim() === '' ? undefined : value, z.string().trim().min(1).max(80).optional());
const dateOfBirthSchema = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Date of birth must use YYYY-MM-DD').superRefine((value, context) => {
  const [year, month, day] = value.split('-').map(Number);
  if (year === undefined || month === undefined || day === undefined) return;
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) context.addIssue({ code: z.ZodIssueCode.custom, message: 'Date of birth is not a valid calendar date' });
});

export const profilePatchSchema = z.object({
  username: usernameSchema.optional(),
  displayName: z.string().trim().min(1).max(80).optional(),
  firstName: z.string().trim().min(1).max(80).optional(),
  middleName: optionalNameSchema,
  lastName: optionalNameSchema,
  dateOfBirth: dateOfBirthSchema.optional(),
  bio: z.string().max(500).nullable().optional(),
  avatarUrl: z.string().trim().max(2048).nullable().optional().refine(value => value == null || /^https?:\/\//.test(value) || /^[^/][^?]*\/[^?]+$/.test(value), 'Avatar must be an HTTPS URL or Eazy media storage path')
}).strict();

export class ProfileService {
  constructor(private readonly pool: Pool, private readonly repository = new ProfileRepository(pool), private readonly storage?: SupabaseStorageProvider) {}

  async getMe(userId: string): Promise<ProfileRecord> {
    const profile = await this.repository.getByUserId(userId);
    if (!profile) throw new AppError('NOT_FOUND', 'Profile not found');
    return { ...profile, avatar_url: await this.resolveAvatar(profile.user_id, profile.avatar_url) };
  }

  async getPublic(username: string, viewerId?: string) {
    const normalized = username.trim().toLowerCase();
    if (!usernamePattern.test(normalized)) throw new AppError('VALIDATION_ERROR', 'Invalid username');
    const profile = await this.repository.getPublicByUsername(normalized, viewerId);
    if (!profile) throw new AppError('NOT_FOUND', 'Profile not found');
    return { username: profile.username, displayName: profile.display_name, firstName: profile.first_name, lastName: profile.last_name, bio: profile.bio, avatarUrl: await this.resolveAvatar(profile.user_id, profile.avatar_url) };
  }

  async getStats(userId: string) {
    return this.repository.getStats(userId);
  }

  async isUsernameAvailable(username: string, currentUserId?: string) {
    const normalized = username.trim().toLowerCase();
    if (!usernamePattern.test(normalized)) throw new AppError('VALIDATION_ERROR', 'Invalid username');
    return { username: normalized, available: await this.repository.usernameAvailable(normalized, currentUserId) };
  }

  async update(userId: string, input: z.infer<typeof profilePatchSchema>): Promise<ProfileRecord> {
    const fields = Object.fromEntries(Object.entries(input).map(([key, value]) => [camelToSnake(key), value]));
    let profile: ProfileRecord | null;
    try {
      profile = await withTransaction(this.pool, client => this.repository.updateCurrent(client, userId, fields));
    } catch (error) {
      if ((error as { code?: string }).code === 'PROFILE_USERNAME_CONFLICT') throw new AppError('CONFLICT', 'That username is already taken');
      throw error;
    }
    if (!profile) throw new AppError('NOT_FOUND', 'Profile not found');
    return { ...profile, avatar_url: await this.resolveAvatar(profile.user_id, profile.avatar_url) };
  }

  private async resolveAvatar(userId: string, value: string | null): Promise<string | null> {
    if (!value) return null;
    if (/^https?:\/\//.test(value)) return value;
    if (!this.storage || !value.startsWith(userId + '/avatar/')) return null;
    try { return (await this.storage.createSignedUrl(value, 3600)).signedUrl; } catch { return null; }
  }

  async completeOnboarding(userId: string): Promise<ProfileRecord> {
    const profile = await withTransaction(this.pool, client => this.repository.completeOnboarding(client, userId));
    if (!profile) throw new AppError('VALIDATION_ERROR', 'Complete username, first name, and date of birth before finishing onboarding');
    return { ...profile, avatar_url: await this.resolveAvatar(profile.user_id, profile.avatar_url) };
  }
}

function camelToSnake(value: string) {
  return value.replace(/[A-Z]/g, character => `_${character.toLowerCase()}`);
}
