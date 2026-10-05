import { AppError } from '../../middleware/errors.js';
import type { BankProvider } from '../../providers/interfaces.js';
export class BankService {
  constructor(private readonly provider: BankProvider) {}
  capabilities() { return this.provider.getCapabilities(); }
  async listBanks(currency: string) {
    try { return { banks: await this.provider.listBanks(currency), currency: currency.toUpperCase() }; }
    catch { throw new AppError('SERVICE_UNAVAILABLE', 'Bank provider is unavailable or not configured'); }
  }
  async resolveAccount(input: { accountNumber: string; bankCode: string }) {
    try {
      const account = await this.provider.resolveAccount(input);
      if (!account) throw new AppError('NOT_FOUND', 'Bank account could not be resolved');
      return { account };
    } catch (error) {
      if (error instanceof AppError) throw error;
      throw new AppError('SERVICE_UNAVAILABLE', 'Bank provider is unavailable or not configured');
    }
  }
}
