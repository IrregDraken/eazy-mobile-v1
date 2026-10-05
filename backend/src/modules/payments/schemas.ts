import { z } from 'zod';
import { currencySchema, moneyAmountSchema } from '../wallet/schemas.js';

export const paymentInitializationSchema = z.discriminatedUnion('purpose', [
  z.object({ purpose: z.literal('wallet_deposit'), amount: moneyAmountSchema, currency: currencySchema }).strict(),
  z.object({ purpose: z.literal('order_purchase'), orderId: z.string().uuid() }).strict()
]);
export const paymentIdParamsSchema = z.object({ id: z.string().uuid() }).strict();
