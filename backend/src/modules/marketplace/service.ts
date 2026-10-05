import { z } from 'zod';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import { MarketplaceRepository, type ProductFilters, type ProductProjection } from './repository.js';
import type { SupabaseStorageProvider } from '../../providers/supabase-storage.js';

const currencySchema = z.string().trim().toUpperCase().regex(/^[A-Z]{3}$/, 'Currency must be a three-letter code');
const priceSchema = z.string().trim().regex(/^\d{1,18}(\.\d{1,2})?$/, 'Price must use a decimal monetary representation');
const mediaSchema = z.object({ storageKey: z.string().trim().min(1).max(1024), position: z.number().int().min(0).max(99) }).strict();
const statusSchema = z.enum(['draft', 'active', 'archived', 'sold_out']);

export const productCreateSchema = z.object({
  name: z.string().trim().min(1).max(200),
  description: z.string().trim().max(5000).optional(),
  categoryId: z.string().uuid().optional(),
  priceAmount: priceSchema,
  currency: currencySchema,
  status: statusSchema.default('draft'),
  media: z.array(mediaSchema).max(12).default([]),
  availableQuantity: z.number().int().min(0).max(1_000_000).default(0)
}).strict();

export const productUpdateSchema = z.object({
  name: z.string().trim().min(1).max(200).optional(),
  description: z.string().trim().max(5000).nullable().optional(),
  categoryId: z.string().uuid().nullable().optional(),
  priceAmount: priceSchema.optional(),
  currency: currencySchema.optional(),
  status: statusSchema.optional()
}).strict().refine(value => Object.keys(value).length > 0, 'At least one product field is required');

export const inventorySchema = z.object({ availableQuantity: z.number().int().min(0).max(1_000_000) }).strict();
export const productIdSchema = z.object({ id: z.string().uuid() });
export const productSearchSchema = z.object({
  q: z.string().trim().min(2).max(80).optional(),
  categoryId: z.string().uuid().optional(),
  sellerId: z.string().uuid().optional(),
  minPrice: priceSchema.optional(),
  maxPrice: priceSchema.optional(),
  currency: currencySchema.optional(),
  availability: z.enum(['in_stock', 'out_of_stock']).optional(),
  status: z.enum(['active', 'sold_out']).optional(),
  sort: z.enum(['newest', 'price_asc', 'price_desc']).default('newest'),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20)
}).strict().superRefine((value, ctx) => {
  if (value.minPrice && value.maxPrice && Number(value.minPrice) > Number(value.maxPrice)) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['maxPrice'], message: 'maxPrice must be greater than or equal to minPrice' });
});

export class MarketplaceService {
  constructor(private readonly pool: Pool, private readonly repository = new MarketplaceRepository(pool), private readonly storage?: SupabaseStorageProvider) {}

  async categories(page = 1, limit = 20) {
    const result = await this.repository.categories(page, limit);
    return { items: result.items, meta: paginationMeta({ page, limit, cursor: undefined }, result.total) };
  }

  async search(input: z.infer<typeof productSearchSchema>, viewerId?: string) {
    const result = await this.repository.products({ ...input, viewerId } as ProductFilters);
    const items = await Promise.all(result.items.map(product => this.attachMediaUrls(product)));
    return { items, meta: paginationMeta(input, result.total) };
  }

  async detail(productId: string, viewerId?: string) {
    const product = await this.repository.getById(productId, viewerId);
    if (!product) throw new AppError('NOT_FOUND', 'Product not found');
    return { product: await this.attachMediaUrls(product) };
  }

  async create(sellerId: string, input: z.infer<typeof productCreateSchema>) {
    const positions = input.media.map(media => media.position);
    if (new Set(positions).size !== positions.length) throw new AppError('VALIDATION_ERROR', 'Media positions must be unique');
    const productId = await withTransaction(this.pool, client => this.repository.create(client, sellerId, input));
    return this.detail(productId, sellerId);
  }

  async update(productId: string, sellerId: string, input: z.infer<typeof productUpdateSchema>) {
    const updated = await withTransaction(this.pool, client => this.repository.update(client, productId, sellerId, input));
    if (!updated) throw new AppError('NOT_FOUND', 'Product not found');
    return this.detail(productId, sellerId);
  }

  async updateInventory(productId: string, sellerId: string, availableQuantity: number) {
    const updated = await withTransaction(this.pool, client => this.repository.updateInventory(client, productId, sellerId, availableQuantity));
    if (!updated) throw new AppError('NOT_FOUND', 'Product inventory not found');
    return this.detail(productId, sellerId);
  }

  private async attachMediaUrls(product: ProductProjection): Promise<ProductProjection> {
    if (!this.storage || product.media.length === 0) return product;
    const storage = this.storage;
    const media = await Promise.all(product.media.map(async item => {
      try {
        return { ...item, url: (await storage.createSignedUrl(item.storageKey, 3600)).signedUrl };
      } catch {
        return { ...item, url: null };
      }
    }));
    return { ...product, media };
  }
}

export type MarketplacePagination = Pagination;
