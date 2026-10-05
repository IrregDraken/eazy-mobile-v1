export interface VirtualAccountRecord {
  userId: string;
  walletId: string;
  provider: string;
  customerCode: string | null;
  accountId: string | null;
  accountNumber: string | null;
  accountName: string | null;
  bankName: string | null;
  bankSlug: string | null;
  currency: string;
  status: 'pending' | 'active' | 'failed' | 'suspended';
  consentedAt: string | null;
  failureReason: string | null;
}

export interface VirtualAccountProviderPayload {
  customerCode?: string;
  accountId?: string;
  accountNumber?: string;
  accountName?: string;
  bankName?: string;
  bankSlug?: string;
  status: 'pending' | 'active' | 'failed';
  failureReason?: string;
}