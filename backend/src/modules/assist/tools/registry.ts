import { z } from 'zod';
import { AppError } from '../../../middleware/errors.js';
import type { MarketplaceService } from '../../marketplace/service.js';
import type { TranslationService } from '../../translation/service.js';
import { translateSchema } from '../../translation/schemas.js';
import { searchProductsInputSchema, type AssistProductResult } from './product-search.js';

export type AssistToolResult =
  | { tool: 'search_products'; products: AssistProductResult[] }
  | { tool: 'translate_text'; translation: { sourceLanguage: string; targetLanguage: string; translatedText: string } };

const searchProductsDefinition = { name: 'search_products', description: 'Search active in-stock Eazy marketplace products. For an explicit budget, provide both maxPrice and the exact three-letter currency code used by the listing.', inputSchema: { type: 'object', additionalProperties: false, required: ['query'], dependentRequired: { maxPrice: ['currency'], currency: ['maxPrice'] }, properties: { query: { type: 'string', minLength: 2, maxLength: 80 }, maxPrice: { type: 'string', pattern: '^\\d{1,18}(\\.\\d{1,2})?$' }, currency: { type: 'string', pattern: '^[A-Za-z]{3}$' } } } };
const translateTextDefinition = { name: 'translate_text', description: 'Translate the supplied text with the configured Eazy Translation service.', inputSchema: { type: 'object', additionalProperties: false, required: ['text', 'targetLanguage'], properties: { text: { type: 'string', minLength: 1, maxLength: 5000 }, targetLanguage: { type: 'string', minLength: 2, maxLength: 35 }, sourceLanguage: { type: 'string', minLength: 2, maxLength: 35 } } } };
const productResultSchema = z.object({
  id: z.string().uuid(),
  name: z.string().max(200),
  description: z.string().max(500).nullable(),
  priceAmount: z.string().regex(/^\d{1,18}(\.\d{1,2})?$/),
  currency: z.string().regex(/^[A-Z]{3}$/),
  status: z.literal('active'),
  available: z.literal(true),
  category: z.string().max(120).nullable(),
  seller: z.object({ username: z.string().max(32), displayName: z.string().max(80) }).strict()
}).strict();
const translationResultSchema = z.object({ sourceLanguage: z.string().max(35), targetLanguage: z.string().max(35), translatedText: z.string().min(1).max(5000) }).strict();

export class AssistToolRegistry {
  constructor(
    private readonly marketplace: Pick<MarketplaceService, 'search'>,
    private readonly translation: Pick<TranslationService, 'translate' | 'capabilities'>
  ) {}

  list() {
    return this.translationAvailable()
      ? [searchProductsDefinition, translateTextDefinition]
      : [searchProductsDefinition];
  }

  async execute(name: string, input: unknown, userId: string): Promise<AssistToolResult> {
    if (name === 'search_products') {
      const parsed = searchProductsInputSchema.safeParse(input);
      if (!parsed.success) throw new AppError('VALIDATION_ERROR', 'Invalid product search request');
      const result = await this.marketplace.search({
        q: parsed.data.query,
        ...(parsed.data.maxPrice && parsed.data.currency ? { maxPrice: parsed.data.maxPrice, currency: parsed.data.currency } : {}),
        sort: 'newest',
        page: 1,
        limit: 5,
        availability: 'in_stock',
        status: 'active'
      }, userId);
      const candidateProducts = result.items.slice(0, 5).map(product => ({
        id: product.id,
        name: truncate(product.name, 200),
        description: product.description === null ? null : truncate(product.description, 500),
        priceAmount: product.priceAmount,
        currency: product.currency,
        status: product.status,
        available: product.availability.inStock,
        category: product.category ? truncate(product.category.name, 120) : null,
        seller: {
          username: truncate(product.seller.username, 32),
          displayName: truncate(product.seller.displayName, 80)
        }
      }));
      const safeProducts = z.array(productResultSchema).max(5).safeParse(candidateProducts);
      if (!safeProducts.success) throw new AppError('INTERNAL_ERROR', 'Marketplace capability data is invalid');
      const products: AssistProductResult[] = safeProducts.data;
      return { tool: 'search_products', products };
    }
    if (name === 'translate_text') {
      if (!this.translationAvailable()) throw new AppError('SERVICE_UNAVAILABLE', 'Eazy Translation provider is unavailable');
      const parsed = translateSchema.safeParse(input);
      if (!parsed.success) throw new AppError('VALIDATION_ERROR', 'Invalid translation request');
      const result = await this.translation.translate(userId, parsed.data);
      const safeTranslation = translationResultSchema.safeParse({ sourceLanguage: result.sourceLanguage, targetLanguage: result.targetLanguage, translatedText: result.translatedText });
      if (!safeTranslation.success) throw new AppError('INTERNAL_ERROR', 'Translation capability data is invalid');
      return {
        tool: 'translate_text',
        translation: safeTranslation.data
      };
    }
    throw new AppError('BAD_REQUEST', 'Unsupported Assist capability');
  }

  private translationAvailable(): boolean {
    try { return this.translation.capabilities().providerAvailable; } catch { return false; }
  }
}

function truncate(value: string, max: number): string {
  return Array.from(value).slice(0, max).join('');
}

export { searchProductsInputSchema } from './product-search.js';
