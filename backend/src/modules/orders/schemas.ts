import { z } from 'zod';

export const orderIdSchema = z.object({ id: z.string().uuid() });
export type OrderIdParams = z.infer<typeof orderIdSchema>;
