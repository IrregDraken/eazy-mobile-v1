import { z } from 'zod';

export const orderIdSchema = z.object({ id: z.string().guid() });
export type OrderIdParams = z.infer<typeof orderIdSchema>;
