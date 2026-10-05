export interface TranslationInput {
  text: string;
  sourceLanguage?: string;
  targetLanguage: string;
}

export interface TranslationProviderResult {
  text: string;
  providerReference?: string;
}

export interface TranslationProviderCapabilities {
  available: boolean;
  /** null means the configured provider has not supplied an authoritative language list. */
  supportedLanguages: readonly string[] | null;
}

export interface TranslationRecord {
  id: string;
  sourceLanguage: string;
  targetLanguage: string;
  originalContent: string;
  translatedContent: string | null;
  status: 'pending' | 'succeeded' | 'failed';
  createdAt: string;
}

export interface TranslationRepositoryContract {
  createPending(userId: string, input: { text: string; sourceLanguage: string; targetLanguage: string }): Promise<Pick<TranslationRecord, 'id' | 'createdAt'>>;
  markSucceeded(userId: string, requestId: string, translatedText: string, providerReference: string | null): Promise<boolean>;
  markFailed(userId: string, requestId: string): Promise<boolean>;
  getForUser(userId: string, requestId: string): Promise<TranslationRecord | null>;
}

export interface TranslationRequestRow {
  id: string;
  source_language: string;
  target_language: string;
  original_content: string;
  translated_content: string | null;
  status: 'pending' | 'succeeded' | 'failed';
  created_at: Date | string;
}

export function normalizeTranslationRecord(row: TranslationRequestRow): TranslationRecord {
  return {
    id: row.id,
    sourceLanguage: row.source_language,
    targetLanguage: row.target_language,
    originalContent: row.original_content,
    translatedContent: row.translated_content,
    status: row.status,
    createdAt: row.created_at instanceof Date ? row.created_at.toISOString() : row.created_at
  };
}

export function isLanguageCode(value: string): boolean {
  try {
    return Intl.getCanonicalLocales(value).length === 1;
  } catch {
    return false;
  }
}

export function canonicalLanguageCode(value: string): string {
  return Intl.getCanonicalLocales(value)[0] ?? value;
}
import type { TranslationProvider } from '../../providers/interfaces.js';

export type { TranslationProvider };
