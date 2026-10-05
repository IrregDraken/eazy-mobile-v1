import { z } from 'zod';
export const bankListSchema = z.object({ currency: z.string().trim().length(3).transform(value => value.toUpperCase()) }).strict();
export const bankResolveSchema = z.object({ accountNumber: z.string().regex(/^\\d{10}$/), bankCode: z.string().trim().min(2).max(20) }).strict();
