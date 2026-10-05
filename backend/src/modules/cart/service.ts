import { z } from 'zod';
import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { CartRepository } from './repository.js';
import { cartItemSchema, cartProductParamSchema, cartQuantitySchema } from './schemas.js';
export { cartItemSchema, cartProductParamSchema, cartQuantitySchema } from './schemas.js';

export class CartService {
  constructor(private readonly pool: Pool, private readonly repository = new CartRepository(pool)) {}

  async get(buyerId: string) {
    try { return { cart: await this.repository.get(buyerId) }; }
    catch (error: unknown) { throw mapCartError(error); }
  }

  async addItem(buyerId: string, input: z.infer<typeof cartItemSchema>) {
    try {
      const cartId = await withTransaction(this.pool, client => this.repository.addItem(client, buyerId, input));
      return { cart: await this.repository.readCart(this.pool, cartId) };
    } catch (error: unknown) { throw mapCartError(error); }
  }

  async updateItem(buyerId: string, productId: string, quantity: number) {
    try {
      const cartId = await withTransaction(this.pool, client => this.repository.updateItem(client, buyerId, productId, quantity));
      if (!cartId) throw new AppError('NOT_FOUND', 'Cart item not found');
      return { cart: await this.repository.readCart(this.pool, cartId) };
    } catch (error: unknown) { throw mapCartError(error); }
  }

  async removeItem(buyerId: string, productId: string) {
    const removed = await withTransaction(this.pool, client => this.repository.removeItem(client, buyerId, productId));
    return { removed };
  }

  async clear(buyerId: string) {
    const cleared = await withTransaction(this.pool, client => this.repository.clear(client, buyerId));
    return { cleared };
  }
}

function mapCartError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  if (error instanceof Error && error.message === 'PRODUCT_UNAVAILABLE') return new AppError('NOT_FOUND', 'Product is unavailable');
  if (error instanceof Error && error.message === 'INSUFFICIENT_INVENTORY') return new AppError('CONFLICT', 'Insufficient inventory');
  if (error instanceof Error && error.message === 'MIXED_CURRENCIES') return new AppError('BAD_REQUEST', 'A cart cannot contain multiple currencies');
  return error instanceof Error ? new AppError('INTERNAL_ERROR', 'Cart operation failed') : new AppError('INTERNAL_ERROR', 'Cart operation failed');
}
