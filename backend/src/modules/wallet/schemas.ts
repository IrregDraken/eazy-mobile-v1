import { z } from 'zod';

export const currencySchema = z.string().trim().regex(/^[A-Za-z]{3}$/).transform(value => value.toUpperCase());

export const moneyAmountSchema = z.string().regex(/^(?:0|[1-9][0-9]{0,17})\.[0-9]{2}$/).refine(value => {
  const [whole, fractional] = value.split('.');
  return BigInt(whole!) * 100n + BigInt(fractional!) > 0n;
}, 'Amount must be greater than zero');

export const createWalletSchema = z.object({ currency: currencySchema }).strict();
export const transferSchema = z.object({
  recipientUsername: z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,32}$/),
  amount: moneyAmountSchema,
  currency: currencySchema
}).strict();

export const walletTransactionParamsSchema = z.object({ id: z.string().uuid() }).strict();
export const walletPaginationSchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(100).default(20)
}).strict();

export function amountToMinorUnits(amount: string): bigint {
  const parsed = moneyAmountSchema.parse(amount);
  const [whole, fraction] = parsed.split('.');
  return BigInt(whole!) * 100n + BigInt(fraction!);
}

export function minorUnitsToAmount(minorUnits: bigint): string {
  if (minorUnits <= 0n) throw new Error('AMOUNT_MUST_BE_POSITIVE');
  return `${minorUnits / 100n}.${String(minorUnits % 100n).padStart(2, '0')}`;
}
