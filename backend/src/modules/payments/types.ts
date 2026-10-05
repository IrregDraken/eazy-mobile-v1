export type PaymentInitializationInput =
  | { purpose: 'wallet_deposit'; amount: string; currency: string }
  | { purpose: 'order_purchase'; orderId: string };
export interface PaymentIntentRecord {
  id: string;
  userId: string;
  walletId: string | null;
  type: 'deposit' | 'purchase';
  status: 'pending' | 'succeeded' | 'failed' | 'reversed';
  amount: string;
  currency: string;
  reference: string;
  idempotencyKey: string;
  orderId: string | null;
  providerName: string;
  providerReference: string | null;
  attemptId: string;
}
export interface PaymentInitializationResult {
  transaction: { id: string; status: 'pending'; amount: string; currency: string; reference: string; orderId: string | null };
  payment: { provider: string; providerReference: string; authorizationUrl?: string };
}
export interface PaymentRepositoryContract {
  lockIdempotencyKey(client: import('../../database/client.js').DbClient, idempotencyKey: string): Promise<void>;
  createIntent(client: import('../../database/client.js').DbClient, input: { id: string; attemptId: string; userId: string; walletId: string | null; type: 'deposit' | 'purchase'; amount: string; currency: string; reference: string; idempotencyKey: string; orderId: string | null; providerName: string; attemptIdempotencyKey: string }): Promise<PaymentIntentRecord>;
  findByIdempotencyKey(client: import('../../database/client.js').DbClient, idempotencyKey: string): Promise<PaymentIntentRecord | null>;
  findOrderForBuyer(client: import('../../database/client.js').DbClient, orderId: string, userId: string): Promise<{ id: string; status: string; currency: string; totalAmount: string } | null>;
  findDepositWallet(client: import('../../database/client.js').DbClient, userId: string, currency: string): Promise<{ id: string; status: string; currency: string } | null>;
  saveProviderReference(client: import('../../database/client.js').DbClient, transactionId: string, attemptId: string, providerReference: string): Promise<boolean>;
  settleProviderPayment?(client: import('../../database/client.js').DbClient, transactionId: string, providerReference: string, amount: string, currency: string): Promise<boolean>;
  getByIdForUser(userId: string, transactionId: string): Promise<PaymentIntentRecord | null>;
  getByProviderReference?(providerReference: string): Promise<PaymentIntentRecord | null>;
}
