import type { BankProvider } from '../../../providers/interfaces.js';
export class UnavailableBankProvider implements BankProvider {
  getCapabilities() { return { available: false, providerName: null, supportsTransfers: false, supportsVirtualAccounts: false }; }
  async listBanks(): Promise<readonly { code: string; name: string; active: boolean }[]> { throw new Error('No bank provider is configured'); }
  async resolveAccount(): Promise<null> { throw new Error('No bank provider is configured'); }
  async createRecipient(): Promise<{ recipientCode: string }> { throw new Error('No bank provider is configured'); }
  async initiateTransfer(): Promise<{ providerReference: string; status: 'pending' | 'success' | 'failed' }> { throw new Error('No bank provider is configured'); }
  async verifyTransfer(): Promise<null> { throw new Error('No bank provider is configured'); }
  verifyWebhookSignature(): boolean { return false; }
  async assignVirtualAccount(): Promise<never> { throw new Error('No bank provider is configured'); }
  async getVirtualAccount(): Promise<null> { throw new Error('No bank provider is configured'); }
}
