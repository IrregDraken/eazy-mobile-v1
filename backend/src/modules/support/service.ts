import { AppError } from '../../middleware/errors.js';
import type { SupportRepository, SupportReportInput } from './repository.js';

export class SupportService {
  constructor(
    private readonly repository: SupportRepository,
    private readonly supportEmail?: string,
  ) {}

  getConfig() {
    return { supportEmail: this.supportEmail?.trim() || null };
  }

  async createReport(userId: string, input: SupportReportInput) {
    try {
      return await this.repository.create(userId, input);
    } catch {
      throw new AppError('SERVICE_UNAVAILABLE', 'Your report could not be saved. Please try again.');
    }
  }
}
