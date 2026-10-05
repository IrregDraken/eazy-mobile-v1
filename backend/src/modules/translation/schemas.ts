import { z } from 'zod';
import { canonicalLanguageCode, isLanguageCode } from './types.js';

const languageCodeSchema = z.string().trim().min(2).max(35)
  .regex(/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/, 'Use a valid BCP 47 language code')
  .refine(isLanguageCode, 'Use a valid BCP 47 language code')
  .transform(canonicalLanguageCode);

export const translateSchema = z.object({
  text: z.string().trim().min(1).max(5000),
  targetLanguage: languageCodeSchema,
  sourceLanguage: languageCodeSchema.optional()
}).strict().superRefine((input, context) => {
  if (input.sourceLanguage && input.sourceLanguage.toLowerCase() === input.targetLanguage.toLowerCase()) {
    context.addIssue({ code: z.ZodIssueCode.custom, path: ['targetLanguage'], message: 'Source and target languages must differ' });
  }
});

export const translationRequestIdSchema = z.object({ requestId: z.string().uuid() }).strict();
