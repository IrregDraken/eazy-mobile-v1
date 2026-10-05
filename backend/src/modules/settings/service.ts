import { AppError } from '../../middleware/errors.js';
import type { SettingsPatch } from './schemas.js';
import type { SettingsRepository } from './repository.js';

export class SettingsService {
  constructor(private readonly repository: SettingsRepository) {}

  async get(userId: string) {
    try { return { settings: await this.repository.get(userId) }; }
    catch { throw new AppError('SERVICE_UNAVAILABLE', 'Settings are temporarily unavailable'); }
  }

  async update(userId: string, patch: SettingsPatch) {
    try { return { settings: await this.repository.update(userId, patch) }; }
    catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError('SERVICE_UNAVAILABLE', 'Settings could not be updated');
    }
  }
}
