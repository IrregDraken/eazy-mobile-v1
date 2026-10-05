import { z } from 'zod';

export const notificationIdSchema = z.object({ id: z.string().uuid() });
export const deviceIdSchema = z.object({ id: z.string().uuid() });
export const deviceRegistrationSchema = z.object({ token: z.string().trim().min(16).max(4096), platform: z.enum(['ios', 'android', 'web']) }).strict();
export type DeviceRegistration = z.infer<typeof deviceRegistrationSchema>;
