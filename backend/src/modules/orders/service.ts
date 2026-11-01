import type { Pool } from 'pg';
import { withTransaction } from '../../database/client.js';
import { AppError } from '../../middleware/errors.js';
import { paginationMeta, type Pagination } from '../../utils/pagination.js';
import { OrderRepository } from './repository.js';

export class OrderService {
  constructor(private readonly pool: Pool, private readonly repository = new OrderRepository(pool)) {}

  async create(buyerId: string, idempotencyKey: string, fulfillments: { sellerId: string; method: 'delivery' | 'pickup'; addressId?: string }[]) {
    try {
      const orderId = await withTransaction(this.pool, client => this.repository.createFromCart(client, buyerId, idempotencyKey, fulfillments));
      const order = await this.repository.get(buyerId, orderId);
      if (!order) throw new AppError('INTERNAL_ERROR', 'Created order could not be read');
      return { order };
    } catch (error: unknown) { throw mapOrderError(error); }
  }

  async addresses(userId: string) {
    return { items: await this.repository.listAddresses(userId) };
  }

  async createAddress(userId: string, input: {
    label: string; recipientName: string; phone: string; state: string; city: string;
    area: string; addressLine: string; landmark?: string | null; isDefault?: boolean;
  }) {
    const address = await withTransaction(this.pool, client => this.repository.createAddress(client, userId, input));
    return { address };
  }

  async updateAddress(userId: string, addressId: string, input: {
    label: string; recipientName: string; phone: string; state: string; city: string;
    area: string; addressLine: string; landmark?: string | null; isDefault?: boolean;
  }) {
    const address = await withTransaction(this.pool, client => this.repository.updateAddress(client, userId, addressId, input));
    if (!address) throw new AppError('NOT_FOUND', 'Delivery address not found');
    return { address };
  }

  async deleteAddress(userId: string, addressId: string) {
    const deleted = await withTransaction(this.pool, client => this.repository.deleteAddress(client, userId, addressId));
    if (!deleted) throw new AppError('NOT_FOUND', 'Delivery address not found');
    return { deleted: true };
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
  if (error.message === 'FULFILLMENT_SELECTION_REQUIRED') return new AppError('VALIDATION_ERROR', 'Choose delivery or pickup for every seller in your bag');
  if (error.message === 'DELIVERY_UNAVAILABLE') return new AppError('CONFLICT', 'A seller has not enabled delivery');
  if (error.message === 'PICKUP_UNAVAILABLE') return new AppError('CONFLICT', 'A seller has not enabled pickup');
  if (error.message === 'DELIVERY_ADDRESS_REQUIRED') return new AppError('VALIDATION_ERROR', 'Choose a delivery address for each delivery seller');
  if (error.message === 'DELIVERY_ADDRESS_NOT_FOUND') return new AppError('NOT_FOUND', 'A selected delivery address is no longer available');
  if (error.message === 'PICKUP_ADDRESS_NOT_ALLOWED') return new AppError('VALIDATION_ERROR', 'Pickup selections cannot include a delivery address');
  if (error.message === 'DELIVERY_CURRENCY_MISMATCH') return new AppError('CONFLICT', 'Seller delivery fee currency does not match the cart');
  if (error.message === 'IDEMPOTENCY_KEY_CONFLICT') return new AppError('CONFLICT', 'Idempotency key belongs to another buyer');
  return new AppError('INTERNAL_ERROR', 'Order creation failed');
}
