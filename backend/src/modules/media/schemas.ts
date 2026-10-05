import { z } from 'zod';
export const mediaUploadSchema = z.object({
  contentType: z.string().trim().min(1).max(100),
  extension: z.string().trim().max(10).optional(),
  kind: z.enum(['avatar','post','message','product'])
}).strict();
export const mediaPathSchema = z.object({ path: z.string().trim().min(1).max(1024) }).strict();