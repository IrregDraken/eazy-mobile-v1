import { z } from 'zod';

export const cartItemSchema = z.object({
  productId: z.string().guid(),
  quantity: z.number().int().min(1).max(100)
}).strict();

export const cartProductParamSchema = z.object({ productId: z.string().guid() });
export const cartQuantitySchema = z.object({ quantity: z.number().int().min(1).max(100) }).strict();

export type CartItemInput = z.infer<typeof cartItemSchema>;
