import { z } from 'zod';

const coordinate = z.number().finite();

export const reverseGeocodeSchema = z.object({
  latitude: coordinate.min(-90).max(90),
  longitude: coordinate.min(-180).max(180)
}).strict();

export const locationSearchSchema = z.object({
  q: z.string().trim().min(2).max(120).refine(value => !/^https?:\/\//i.test(value), 'URL proxy requests are not supported'),
  limit: z.coerce.number().int().min(1).max(10).default(5)
}).strict();
