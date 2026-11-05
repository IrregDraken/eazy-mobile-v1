import { z } from 'zod';

export const virtualAccountAssignSchema = z.object({
  consent: z.literal(true),
  firstName: z.string().trim().min(1).max(80),
  middleName: z.string().trim().max(80).optional(),
  lastName: z.string().trim().min(1).max(80),
  phone: z.string().trim().regex(/^\+?[1-9]\d{7,14}$/),
  preferredBank: z.string().trim().min(2).max(64),
  country: z.literal('NG'),
  accountNumber: z.string().regex(/^\d{10}$/),
  bvn: z.string().regex(/^\d{11}$/),
  bankCode: z.string().regex(/^\d{3,6}$/),
}).strict();
