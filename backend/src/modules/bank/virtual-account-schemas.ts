import { z } from 'zod';

export const virtualAccountAssignSchema = z.object({ consent: z.literal(true) }).strict();