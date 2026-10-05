import { z } from 'zod';
import { canonicalLanguageCode, isLanguageCode } from '../translation/types.js';

const languageCodeSchema = z.string().trim().min(2).max(35).refine(isLanguageCode, 'Language must be a valid BCP-47 language tag').transform(canonicalLanguageCode);

export const settingsPatchSchema = z.object({
  languageCode: languageCodeSchema.optional(),
  theme: z.enum(['system', 'light', 'dark']).optional(),
  notifications: z.object({
    follows: z.boolean().optional(),
    likes: z.boolean().optional(),
    comments: z.boolean().optional()
  }).strict().refine(value => Object.keys(value).length > 0, 'At least one notification preference is required').optional()
}).strict().refine(value => Object.keys(value).length > 0, 'At least one setting is required');

export type SettingsPatch = z.infer<typeof settingsPatchSchema>;
