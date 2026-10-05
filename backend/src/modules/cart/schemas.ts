import { z } from 'zod';

export const cartItemSchema = z.object({
  productId: z.string().uuid(),
  quantity: z.number().int().min(1).max(100)
}).strict();

export const cartProductParamSchema = z.object({ productId: z.string().uuid() });
export const cartQuantitySchema = z.object({ quantity: z.number().int().min(1).max(100) }).strict();

export type CartItemInput = z.infer<typeof cartItemSchema>;
