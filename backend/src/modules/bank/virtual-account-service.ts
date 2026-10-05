import { createHash } from 'node:crypto';
import type { Pool } from 'pg';
import { withTransaction, type DbClient } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import type { BankProvider } from '../../providers/interfaces.js';
import type { LedgerService } from '../ledger/service.js';
import { amountToMinorUnits, minorUnitsToAmount } from '../wallet/schemas.js';
import { VirtualAccountRepository } from './virtual-account-repository.js';
import type { VirtualAccountRecord } from './virtual-account-types.js';

export class VirtualAccountService {
  private readonly repository: VirtualAccountRepository;

  constructor(private readonly pool: Pool, private readonly provider: BankProvider, private readonly ledger: LedgerService) {
    this.repository = new VirtualAccountRepository(pool);
  }

  capabilities() {
    const capabilities = this.provider.getCapabilities();
    return {
      providerAvailable: capabilities.available,
      virtualAccountsAvailable: capabilities.available && capabilities.supportsVirtualAccounts,
      providerName: capabilities.providerName
    };
  }

  async get(userId: string) {
    let account = await this.repository.findByUser(userId);
    if (account?.status === 'pending' && account.customerCode) {
      try {
        const current = await this.provider.getVirtualAccount({ customerCode: account.customerCode });
        if (current) {
          const saved = await withTransaction(this.pool, client => this.repository.saveProviderState(client, userId, current));
          account = saved ?? account;
        }
      } catch {
        // Keep the persisted pending state. Webhooks remain the authoritative assignment signal.
      }
    }
    return { virtualAccount: account ? this.safeProjection(account) : null };
  }

  async assign(userId: string, consent: boolean) {
    if (!consent) throw new AppError('BAD_REQUEST', 'Explicit consent is required before creating a dedicated bank account');

    const capabilities = this.capabilities();
    if (!capabilities.virtualAccountsAvailable) {
      throw new AppError('SERVICE_UNAVAILABLE', 'Bank receiving is unavailable or not configured');
    }

    const user = await this.readUser(userId);
    if (!user.email || !user.phone || !user.displayName) {
      throw new AppError('CONFLICT', 'Complete your name, email, and phone number before creating a bank receiving account');
    }

    const wallet = await withTransaction(this.pool, async client => {
      const result = await client.query<{ id: string; status: string; currency: string }>(
        `SELECT id, status, trim(currency) AS currency FROM wallets WHERE user_id = $1 FOR UPDATE`, [userId]
      );
      const row = result.rows[0];
      if (!row) throw new AppError('NOT_FOUND', 'Wallet not found');
      if (row.status !== 'active') throw new AppError('CONFLICT', 'Wallet is not active');
      if (row.currency !== 'NGN') throw new AppError('BAD_REQUEST', 'Bank receiving currently supports NGN wallet accounts');
      return row;
    });

    let account = await this.repository.findByUser(userId);
    if (account?.status === 'active' && account.accountNumber) return { virtualAccount: this.safeProjection(account) };

    if (!account) {
      account = await withTransaction(this.pool, client =>
        this.repository.createPending(client, { userId, walletId: wallet.id, provider: capabilities.providerName!, currency: 'NGN' })
      );
    }

    if (account.status === 'pending' && account.customerCode) {
      try {
        const current = await this.provider.getVirtualAccount({ customerCode: account.customerCode });
        if (current) {
          const saved = await withTransaction(this.pool, client =>
            this.repository.saveProviderState(client, userId, current)
          );
          if (saved?.status === 'active') return { virtualAccount: this.safeProjection(saved) };
          account = saved ?? account;
        }
      } catch {
        return { virtualAccount: this.safeProjection(account) };
      }
    }

    if (account.status === 'pending' && account.customerCode) {
      return { virtualAccount: this.safeProjection(account) };
    }

    try {
      const [firstName, ...rest] = user.displayName.trim().split(/\s+/);
      const state = await this.provider.assignVirtualAccount({
        email: user.email,
        firstName: firstName || 'Eazy',
        lastName: rest.join(' ') || 'User',
        phone: user.phone,
        currency: 'NGN'
      });
      const saved = await withTransaction(this.pool, client =>
        this.repository.saveProviderState(client, userId, state)
      );
      return { virtualAccount: saved ? this.safeProjection(saved) : this.safeProjection(account) };
    } catch {
      await withTransaction(this.pool, client =>
        this.repository.saveProviderState(client, userId, {
          status: 'failed',
          failureReason: 'Virtual bank account assignment could not be completed'
        })
      );
      throw new AppError('SERVICE_UNAVAILABLE', 'Bank receiving account could not be created. Provider configuration or account eligibility may be required.');
    }
  }

  async handleWebhook(event: string, data: Record<string, any>) {
    if (event === 'dedicatedaccount.assign.success') {
      const customerCode = this.customerCodeFrom(data);
      if (!customerCode) return { handled: false };
      const account = await this.readByCustomerCode(customerCode);
      if (!account) return { handled: false };
      const state = this.providerPayloadFromWebhook(data, customerCode);
      await withTransaction(this.pool, client => this.repository.saveProviderState(client, account.userId, state));
      return { handled: true, type: 'assignment', userId: account.userId };
    }

    if (event === 'dedicatedaccount.assign.failed' || event === 'assigndedicatedaccount.failed') {
      const customerCode = this.customerCodeFrom(data);
      if (!customerCode) return { handled: false };
      const account = await this.readByCustomerCode(customerCode);
      if (!account) return { handled: false };
      await withTransaction(this.pool, client => this.repository.saveProviderState(client, account.userId, {
        status: 'failed',
        customerCode,
        failureReason: typeof data.reason === 'string' ? data.reason.slice(0, 500) : 'Virtual account assignment failed'
      }));
      return { handled: true, type: 'assignment_failed', userId: account.userId };
    }

    if (event !== 'charge.success') return { handled: false };

    const reference = typeof data.reference === 'string' ? data.reference.trim() : '';
    const amountMinor = Number(data.amount);
    const currency = typeof data.currency === 'string' ? data.currency.trim().toUpperCase() : '';
    if (!reference || !Number.isSafeInteger(amountMinor) || amountMinor <= 0 || !currency) return { handled: false };

    const customerCode = this.customerCodeFrom(data);
    const accountNumber = this.accountNumberFrom(data);
    const account = customerCode
      ? await this.readByCustomerCode(customerCode)
      : accountNumber ? await this.readByAccountNumber(accountNumber) : null;
    if (!account || account.status !== 'active') return { handled: false };

    if (account.accountNumber && accountNumber && account.accountNumber !== accountNumber) {
      throw new AppError('CONFLICT', 'Virtual account webhook account does not match the assigned account');
    }

    const amount = minorUnitsToAmount(BigInt(amountMinor));
    const idempotencyKey = createHash('sha256').update(`dva-charge:${reference}`).digest('hex');
    const transaction = await withTransaction(this.pool, async client => {
      await client.query('SELECT pg_advisory_xact_lock(hashtext($1))', [`dva-charge:${reference}`]);

      const existing = await client.query<{ id: string; status: string }>(
        'SELECT id, status FROM transactions WHERE idempotency_key = $1 LIMIT 1 FOR UPDATE', [idempotencyKey]
      );
      if (existing.rows[0]) return existing.rows[0];

      const created = await client.query<{ id: string }>(
        `INSERT INTO transactions (user_id, wallet_id, type, status, amount, currency, reference, idempotency_key, provider_reference)
         VALUES ($1, $2, 'deposit', 'succeeded', $3::numeric(20,2), $4, $5, $6, $7)
         RETURNING id`,
        [account.userId, account.walletId, amount, currency, reference, idempotencyKey, reference]
      );
      const id = created.rows[0]!.id;

      await this.ledger.createInboundDeposit(client, {
        transactionId: id,
        walletId: account.walletId,
        amount,
        currency,
        providerReference: reference
      });
      return { id, status: 'succeeded' };
    });

    return { handled: true, type: 'deposit', transactionId: transaction.id };
  }

  private async readUser(userId: string) {
    const result = await this.pool.query<{ email: string | null; phone: string | null; displayName: string }>(
      `SELECT u.email, u.phone, p.display_name AS "displayName"
       FROM users u JOIN profiles p ON p.user_id = u.id
       WHERE u.id = $1 AND u.status = 'active' LIMIT 1`, [userId]
    );
    if (!result.rows[0]) throw new AppError('NOT_FOUND', 'User profile not found');
    return result.rows[0];
  }

  private async readByCustomerCode(customerCode: string) {
    const client = await this.pool.connect();
    try { return await this.repository.findByCustomerCode(client, 'paystack', customerCode); }
    finally { client.release(); }
  }

  private async readByAccountNumber(accountNumber: string) {
    const client = await this.pool.connect();
    try { return await this.repository.findByAccountNumber(client, 'paystack', accountNumber); }
    finally { client.release(); }
  }

  private customerCodeFrom(data: Record<string, any>) {
    return String(data.customer_code ?? data.customer?.customer_code ?? data.customer?.code ?? '').trim() || null;
  }

  private accountNumberFrom(data: Record<string, any>) {
    return String(data.dedicated_account?.account_number ?? data.receiver?.account_number ?? data.account_number ?? '').trim() || null;
  }

  private providerPayloadFromWebhook(data: Record<string, any>, customerCode: string) {
    const account = data.dedicated_account ?? data.account ?? data;
    const accountNumber = this.accountNumberFrom(data);
    return {
      customerCode,
      accountId: account?.id !== undefined ? String(account.id) : undefined,
      accountNumber: accountNumber || undefined,
      accountName: account?.account_name ? String(account.account_name) : undefined,
      bankName: account?.bank?.name ? String(account.bank.name) : account?.bank_name ? String(account.bank_name) : undefined,
      bankSlug: account?.bank?.slug ? String(account.bank.slug) : account?.provider_slug ? String(account.provider_slug) : undefined,
      status: accountNumber ? 'active' as const : 'pending' as const
    };
  }

  private safeProjection(account: VirtualAccountRecord) {
    return {
      provider: account.provider,
      status: account.status,
      accountNumber: account.accountNumber,
      accountName: account.accountName,
      bankName: account.bankName,
      currency: account.currency,
      consentedAt: account.consentedAt,
      failureReason: account.failureReason
    };
  }
}