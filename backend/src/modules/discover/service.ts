import { z } from 'zod';
import { AppError } from '../../middleware/errors.js';
import { SocialService, searchQuerySchema } from '../social/service.js';
import { MarketplaceService, productSearchSchema } from '../marketplace/service.js';

export const discoverQuerySchema = z.object({
  type: z.enum(['people', 'products', 'categories']).default('products'),
  q: z.string().trim().min(2).max(80).optional(),
  categoryId: z.string().uuid().optional(),
  sellerId: z.string().uuid().optional(),
  minPrice: z.string().trim().regex(/^\d{1,18}(\.\d{1,2})?$/).optional(),
  maxPrice: z.string().trim().regex(/^\d{1,18}(\.\d{1,2})?$/).optional(),
  availability: z.enum(['in_stock', 'out_of_stock']).optional(),
  status: z.enum(['active', 'sold_out']).optional(),
  sort: z.enum(['newest', 'price_asc', 'price_desc']).default('newest'),
  page: z.coerce.number().int().min(1).default(1),
  limit: z.coerce.number().int().min(1).max(50).default(20)
}).strict();

export class DiscoverService {
  constructor(private readonly marketplace: MarketplaceService, private readonly social: SocialService) {}

  async unified(input: z.infer<typeof discoverQuerySchema>, viewerId?: string) {
    if (input.type === 'people') {
      if (!viewerId) throw new AppError('UNAUTHORIZED', 'Authentication required for people discovery');
      if (!input.q) throw new AppError('VALIDATION_ERROR', 'q is required for people discovery');
      return { type: 'people', ...(await this.social.search(viewerId, searchQuerySchema.parse({ q: input.q, page: input.page, limit: input.limit }))) };
    }
    if (input.type === 'categories') return { type: 'categories', ...(await this.marketplace.categories(input.page, input.limit)) };
    // Keep the unified discovery discriminator out of the marketplace schema.
    // Both schemas remain strict, while each service receives only its own fields.
    const { type: _type, ...productInput } = input;\n    return { type: 'products', ...(await this.marketplace.search(productSearchSchema.parse(productInput), viewerId)) };
  }

  async products(input: z.infer<typeof productSearchSchema>, viewerId?: string) {
    return this.marketplace.search(input, viewerId);
  }
}
