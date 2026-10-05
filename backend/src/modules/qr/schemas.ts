import { z } from 'zod';
import { currencySchema, moneyAmountSchema } from '../wallet/schemas.js';

export const qrCreateSchema = z.object({ expiresInDays: z.coerce.number().int().min(1).max(90).default(30) }).strict();
export const qrTokenSchema = z.string().regex(/^[A-Za-z0-9_-]{40,100}$/);
export const qrResolveSchema = z.object({ token: qrTokenSchema }).strict();
export const qrPaymentSchema = z.object({ token: qrTokenSchema, amount: moneyAmountSchema, currency: currencySchema }).strict();
export const qrIdSchema = z.object({ id: z.string().uuid() }).strict();
