export interface AuthProvider { validateToken(token: string): Promise<{ subject: string }>; }
export interface EmailProvider { send(input: { to: string; subject: string; body: string }): Promise<void>; }
export interface PaymentProvider {
  getCapabilities(): { available: boolean; providerName: string | null };
  createPayment(input: { amount: string; currency: string; reference: string }): Promise<{ providerReference: string; authorizationUrl?: string }>;
  verifyPayment?(providerReference: string): Promise<{ providerReference: string; amount: string; currency: string } | null>;
  verifyWebhookSignature?(rawBody: string, signature: string | undefined): boolean;
}
export interface AIProviderMessage { role: 'system' | 'user' | 'assistant'; content: string; }
export interface AIProvider {
  getCapabilities(): { available: boolean; providerName: string | null };
  complete(input: { messages: readonly AIProviderMessage[]; jsonMode: boolean; maxOutputTokens: number }): Promise<{ text: string; providerReference?: string }>;
}
export interface TranslationProvider {
  translate(input: { text: string; source?: string; target: string }): Promise<{ text: string; providerReference?: string }>;
  getCapabilities(): { available: boolean; supportedLanguages: readonly string[] | null };
}
export interface ProviderLocationResult {
  formattedAddress?: string | null;
  city?: string | null;
  region?: string | null;
  country?: string | null;
  countryCode?: string | null;
  latitude?: number | null;
  longitude?: number | null;
  providerPlaceId?: string | null;
}
export interface LocationProviderCapabilities { available: boolean; reverseGeocode: boolean; search: boolean; }
export interface LocationProvider {
  reverseGeocode(input: { latitude: number; longitude: number }): Promise<ProviderLocationResult>;
  search(input: { query: string; limit: number }): Promise<ProviderLocationResult[]>;
  getCapabilities(): LocationProviderCapabilities;
}
export interface NotificationProvider { notify(input: { userId: string; title: string; body: string }): Promise<void>; }
export interface StorageProvider { put(input: { key: string; contentType: string; bytes: Uint8Array }): Promise<{ url: string }>; }

export interface BankProvider {
  getCapabilities(): { available: boolean; providerName: string | null; supportsTransfers: boolean; supportsVirtualAccounts: boolean };
  listBanks(currency: string): Promise<readonly { code: string; name: string; active: boolean }[]>;
  resolveAccount(input: { accountNumber: string; bankCode: string }): Promise<{ accountNumber: string; accountName: string; bankCode: string; bankName: string } | null>;
  createRecipient(input: { name: string; accountNumber: string; bankCode: string; currency: string }): Promise<{ recipientCode: string }>;
  initiateTransfer(input: { recipientCode: string; amount: string; currency: string; reference: string; reason?: string }): Promise<{ providerReference: string; status: 'pending' | 'success' | 'failed' }>;
  verifyTransfer(providerReference: string): Promise<{ providerReference: string; amount: string; currency: string; status: 'pending' | 'success' | 'failed' | 'reversed' } | null>;
  verifyWebhookSignature(rawBody: string, signature: string | undefined): boolean;
  assignVirtualAccount(input: { email: string; firstName: string; lastName: string; phone: string; currency: string }): Promise<{ customerCode?: string; accountId?: string; accountNumber?: string; accountName?: string; bankName?: string; bankSlug?: string; status: 'pending' | 'active' | 'failed'; failureReason?: string }>;
  getVirtualAccount(input: { customerCode?: string; accountNumber?: string }): Promise<{ customerCode?: string; accountId?: string; accountNumber?: string; accountName?: string; bankName?: string; bankSlug?: string; status: 'pending' | 'active' | 'failed'; failureReason?: string } | null>;
}
