import { z } from 'zod';
import { currencySchema, moneyAmountSchema } from '../wallet/schemas.js';

export const bankTransferSchema = z.object({
  accountNumber: z.string().regex(/^\d{10}$/),
  bankCode: z.string().trim().min(2).max(20),
  accountName: z.string().trim().min(2).max(120),
  bankName: z.string().trim().max(120).optional(),
  amount: moneyAmountSchema,
  currency: currencySchema,
  reason: z.string().trim().max(140).optional()
}).strict();

export const bankTransferParamsSchema = z.object({ id: z.string().uuid() }).strict();