import { z } from 'zod';

export const orderIdSchema = z.object({ id: z.string().guid() });
export type OrderIdParams = z.infer<typeof orderIdSchema>;

export const addressIdSchema = z.object({ id: z.string().guid() });
export const deliveryAddressSchema = z.object({
  label: z.string().trim().min(1).max(40),
  recipientName: z.string().trim().min(2).max(120),
  phone: z.string().trim().regex(/^\+?[0-9 ()-]{7,24}$/),
  state: z.string().trim().min(2).max(80),
  city: z.string().trim().min(2).max(80),
  area: z.string().trim().min(2).max(120),
  addressLine: z.string().trim().min(5).max(240),
  landmark: z.string().trim().max(160).nullable().optional(),
  isDefault: z.boolean().default(false)
}).strict();

export const orderCreateSchema = z.object({
  fulfillments: z.array(z.object({
    sellerId: z.string().guid(),
    method: z.enum(['delivery', 'pickup']),
    addressId: z.string().guid().optional()
  }).strict()).min(1).max(20)
}).strict().superRefine((value, context) => {
  const ids = value.fulfillments.map(item => item.sellerId);
  if (new Set(ids).size !== ids.length) {
    context.addIssue({ code: 'custom', path: ['fulfillments'], message: 'Choose one fulfillment method per seller' });
  }
});
