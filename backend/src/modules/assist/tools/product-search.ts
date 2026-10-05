import { z } from 'zod';

const priceSchema = z.string().trim().regex(/^\d{1,18}(\.\d{1,2})?$/);
const currencySchema = z.string().trim().toUpperCase().regex(/^[A-Z]{3}$/);

export const searchProductsInputSchema = z.object({
  query: z.string().trim().min(2).max(80),
  maxPrice: priceSchema.optional(),
  currency: currencySchema.optional()
}).strict().superRefine((input, context) => {
  if (input.maxPrice && !input.currency) context.addIssue({ code: z.ZodIssueCode.custom, path: ['currency'], message: 'A currency is required with a maximum price' });
  if (input.currency && !input.maxPrice) context.addIssue({ code: z.ZodIssueCode.custom, path: ['maxPrice'], message: 'A maximum price is required with a currency filter' });
});

export interface AssistProductResult {
  id: string;
  name: string;
  description: string | null;
  priceAmount: string;
  currency: string;
  status: string;
  available: boolean;
  category: string | null;
  seller: { username: string; displayName: string };
}
