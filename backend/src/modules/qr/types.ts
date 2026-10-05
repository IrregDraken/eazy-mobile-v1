import type { DbClient } from '../../database/client.js';

export interface QrRecord {
  id: string;
  ownerId: string;
  username: string;
  displayName: string;
  status: 'active' | 'used' | 'expired' | 'revoked';
  expiresAt: string | null;
}
export interface QrRepositoryContract {
  create(client: DbClient, input: { ownerId: string; codeHash: string; expiresAt: string }): Promise<{ id: string; createdAt: string } | null>;
  resolve(codeHash: string): Promise<QrRecord | null>;
  resolveForPayment(client: DbClient, codeHash: string, allowInactive: boolean): Promise<QrRecord | null>;
  revoke(ownerId: string, qrId: string): Promise<boolean>;
}
export interface QrCreateResult {
  qr: { id: string; content: string; expiresAt: string };
}
