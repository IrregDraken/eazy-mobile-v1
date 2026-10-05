import { createHash, randomBytes } from 'node:crypto';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import type { DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { QrRepositoryContract } from './types.js';

export class QrService {
  constructor(private readonly pool: Pool, private readonly repository: QrRepositoryContract) {}

  async create(ownerId: string, expiresInDays: number) {
    const token = randomBytes(32).toString('base64url');
    const expiresAt = new Date(Date.now() + expiresInDays * 86_400_000).toISOString();
    const qr = await withTransaction(this.pool, client => this.repository.create(client, {
      ownerId,
      codeHash: this.hash(token),
      expiresAt
    }));
    if (!qr) throw new AppError('NOT_FOUND', 'QR owner is not available');
    return { qr: { id: qr.id, content: token, expiresAt } };
  }

  async resolve(token: string) {
    const qr = await this.getQr(token);
    return { recipient: { username: qr.username, displayName: qr.displayName } };
  }

  async resolveForPayment(client: DbClient, token: string, allowInactive: boolean) {
    const qr = await this.repository.resolveForPayment(client, this.hash(token), allowInactive);
    if (!qr) throw new AppError('NOT_FOUND', 'QR payment recipient not found or expired');
    return { userId: qr.ownerId, username: qr.username, displayName: qr.displayName };
  }

  async revoke(ownerId: string, qrId: string) {
    if (!await this.repository.revoke(ownerId, qrId)) throw new AppError('NOT_FOUND', 'QR code not found');
    return { revoked: true };
  }

  private hash(token: string): string { return createHash('sha256').update(token).digest('hex'); }

  private async getQr(token: string) {
    const qr = await this.repository.resolve(this.hash(token));
    if (!qr) throw new AppError('NOT_FOUND', 'QR payment recipient not found or expired');
    return qr;
  }
}
