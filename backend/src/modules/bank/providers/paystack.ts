import crypto from 'node:crypto';
import type { AppConfig } from '../../../config/env.js';
import type { BankProvider } from '../../../providers/interfaces.js';

export class PaystackBankProvider implements BankProvider {
  private readonly secretKey: string;
  private readonly enabled: boolean;
  constructor(private readonly config: AppConfig) {
    this.secretKey = config.PAYSTACK_SECRET_KEY ?? '';
    this.enabled = config.PAYSTACK_ENABLED === true && Boolean(this.secretKey);
  }
  getCapabilities() {
    return { available: this.enabled, providerName: this.enabled ? 'paystack' : null, supportsTransfers: this.enabled, supportsVirtualAccounts: this.enabled };
  }
  async listBanks(currency: string) {
    this.assertEnabled();
    const response = await this.request(`/bank?currency=${encodeURIComponent(currency.toUpperCase())}`);
    const data = Array.isArray(response.data) ? response.data : [];
    return data.map((bank: any) => ({ code: String(bank.code ?? ''), name: String(bank.name ?? ''), active: bank.active !== false })).filter((bank: {code:string;name:string}) => bank.code && bank.name);
  }
  async createRecipient(input: { name: string; accountNumber: string; bankCode: string; currency: string }) {
    this.assertEnabled();
    const response = await this.request('/transferrecipient', { method: 'POST', body: JSON.stringify({ type: 'nuban', name: input.name, account_number: input.accountNumber, bank_code: input.bankCode, currency: input.currency }) });
    const code = String(response.data?.recipient_code ?? '').trim();
    if (!code) throw new Error('Bank provider did not return a recipient code');
    return { recipientCode: code };
  }
  async initiateTransfer(input: { recipientCode: string; amount: string; currency: string; reference: string; reason?: string }) {
    this.assertEnabled();
    const response = await this.request('/transfer', { method: 'POST', body: JSON.stringify({ source: 'balance', amount: amountToMinorUnits(input.amount), recipient: input.recipientCode, reference: input.reference, currency: input.currency, reason: input.reason }) });
    const providerReference = String(response.data?.reference ?? '').trim();
    if (!providerReference) throw new Error('Bank provider did not return a transfer reference');
    const status = String(response.data?.status ?? 'pending').toLowerCase();
    return { providerReference, status: status === 'success' ? 'success' as const : status === 'failed' ? 'failed' as const : 'pending' as const };
  }
  async verifyTransfer(providerReference: string) {
    this.assertEnabled();
    const response = await this.request(`/transfer/verify/${encodeURIComponent(providerReference)}`);
    const data = response.data as { reference?: string; amount?: number; currency?: string; status?: string } | undefined;
    const reference = data?.reference?.trim();
    const amount = data?.amount;
    const currency = data?.currency?.trim().toUpperCase();
    if (!reference || !Number.isSafeInteger(amount) || !currency) return null;
    const status = String(data?.status ?? 'pending').toLowerCase();
    return { providerReference: reference, amount: minorUnitsToAmount(amount as number), currency, status: status === 'success' ? 'success' as const : status === 'failed' ? 'failed' as const : status === 'reversed' ? 'reversed' as const : 'pending' as const };
  }
  verifyWebhookSignature(rawBody: string, signature: string | undefined) {
    if (!signature || !this.secretKey) return false;
    const expected = crypto.createHmac('sha512', this.secretKey).update(rawBody).digest('hex');
    const expectedBuffer = Buffer.from(expected);
    const actualBuffer = Buffer.from(signature);
    return expectedBuffer.length === actualBuffer.length && crypto.timingSafeEqual(expectedBuffer, actualBuffer);
  }


  async assignVirtualAccount(input: { email: string; firstName: string; lastName: string; phone: string; currency: string }) {
    this.assertEnabled();
    if (input.currency.toUpperCase() !== 'NGN') throw new Error('Dedicated virtual accounts currently require NGN');

    let customer: any;
    try {
      customer = (await this.request(`/customer/${encodeURIComponent(input.email)}`)).data;
    } catch {
      customer = (await this.request('/customer', {
        method: 'POST',
        body: JSON.stringify({
          email: input.email,
          first_name: input.firstName,
          last_name: input.lastName,
          phone: input.phone
        })
      })).data;
    }

    const customerCode = String(customer?.customer_code ?? '').trim();
    if (!customerCode) throw new Error('Bank provider did not return a customer code');

    const response = await this.request('/dedicated_account', {
      method: 'POST',
      body: JSON.stringify({
        customer: customerCode,
        preferred_bank: this.config.PAYSTACK_MODE === 'test' ? 'test-bank' : undefined,
        first_name: input.firstName,
        last_name: input.lastName,
        phone: input.phone
      })
    });

    return this.virtualAccountFromPayload(response.data, 'pending');
  }

  async getVirtualAccount(input: { customerCode?: string; accountNumber?: string }) {
    this.assertEnabled();
    const key = input.customerCode || input.accountNumber;
    if (!key) return null;
    const response = await this.request(`/customer/${encodeURIComponent(key)}`);
    const data = response.data as any;
    if (!data) return null;
    return this.virtualAccountFromPayload(data, data.dedicated_account ? 'active' : 'pending');
  }

  private virtualAccountFromPayload(data: any, fallbackStatus: 'pending' | 'active' | 'failed') {
    const account = data?.dedicated_account ?? data?.dedicatedAccount ?? data;
    const accountNumber = account?.account_number ? String(account.account_number) : undefined;
    const accountId = account?.id !== undefined ? String(account.id) : undefined;
    const accountName = account?.account_name ? String(account.account_name) : undefined;
    const bankName = account?.bank?.name ? String(account.bank.name) : account?.bank_name ? String(account.bank_name) : undefined;
    const bankSlug = account?.bank?.slug ? String(account.bank.slug) : account?.provider_slug ? String(account.provider_slug) : undefined;
    const customerCode = data?.customer_code ? String(data.customer_code) : undefined;
    return {
      customerCode,
      accountId,
      accountNumber,
      accountName,
      bankName,
      bankSlug,
      status: accountNumber ? 'active' as const : fallbackStatus,
      failureReason: data?.reason ? String(data.reason) : undefined
    };
  }

  async resolveAccount(input: { accountNumber: string; bankCode: string }) {
    this.assertEnabled();
    const response = await this.request(`/bank/resolve?account_number=${encodeURIComponent(input.accountNumber)}&bank_code=${encodeURIComponent(input.bankCode)}`);
    const data = response.data as { account_number?: string; account_name?: string } | undefined;
    if (!data?.account_number || !data.account_name) return null;
    return { accountNumber: data.account_number, accountName: data.account_name, bankCode: input.bankCode, bankName: '' };
  }
  private async request(path: string, init: RequestInit = {}): Promise<{ status?: boolean; message?: string; data?: any }> {
    const response = await fetch(`https://api.paystack.co${path}`, { ...init, headers: { authorization: `Bearer ${this.secretKey}`, 'content-type': 'application/json', ...(init.headers ?? {}) } });
    const payload = await response.json() as { status?: boolean; message?: string; data?: any };
    if (!response.ok || payload.status !== true) throw new Error(payload.message ?? 'Bank provider request failed');
    return payload;
  }
  private assertEnabled() { if (!this.enabled) throw new Error('Paystack bank provider is not configured'); }
}

function amountToMinorUnits(amount: string): number {
  const [whole, fraction = ''] = amount.split('.');
  const value = Number(whole) * 100 + Number(fraction.padEnd(2, '0').slice(0, 2));
  if (!Number.isSafeInteger(value) || value <= 0) throw new Error('Bank transfer amount is invalid');
  return value;
}
function minorUnitsToAmount(value: number): string { return (value / 100).toFixed(2); }
