import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import { OrderRepository } from './repository.js';

export class OrderService {
  constructor(private readonly pool: Pool, private readonly repository = new OrderRepository(pool)) {}

  async create(buyerId: string, idempotencyKey: string) {
    try {
      const orderId = await withTransaction(this.pool, client => this.repository.createFromCart(client, buyerId, idempotencyKey));
      const order = await this.repository.get(buyerId, orderId);
      if (!order) throw new AppError('INTERNAL_ERROR', 'Created order could not be read');
      return { order };
    } catch (error: unknown) { throw mapOrderError(error); }
  }

  async get(buyerId: string, orderId: string) {
    const order = await this.repository.get(buyerId, orderId);
    if (!order) throw new AppError('NOT_FOUND', 'Order not found');
    return { order };
  }

  async list(buyerId: string, pagination: Pagination) {
    const result = await this.repository.list(buyerId, pagination.page, pagination.limit);
    return { items: result.items, meta: paginationMeta(pagination, result.total) };
  }
}

function mapOrderError(error: unknown): AppError {
  if (error instanceof AppError) return error;
  if (!(error instanceof Error)) return new AppError('INTERNAL_ERROR', 'Order creation failed');
  if (error.message === 'EMPTY_CART') return new AppError('BAD_REQUEST', 'Cannot create an order from an empty cart');
  if (error.message === 'INSUFFICIENT_INVENTORY') return new AppError('CONFLICT', 'Insufficient inventory');
  if (error.message === 'MIXED_CURRENCIES') return new AppError('BAD_REQUEST', 'An order cannot contain multiple currencies');
  if (error.message === 'IDEMPOTENCY_KEY_CONFLICT') return new AppError('CONFLICT', 'Idempotency key belongs to another buyer');
  return new AppError('INTERNAL_ERROR', 'Order creation failed');
}
