import assert from 'node:assert/strict';
import test from 'node:test';
import { AppError } from '../src/middleware/errors.js';
import { CartService, cartItemSchema, cartQuantitySchema } from '../src/modules/cart/service.js';
import type { CartRepository } from '../src/modules/cart/repository.js';
import { OrderService } from '../src/modules/orders/service.js';
import type { OrderRepository } from '../src/modules/orders/repository.js';

function fakePool() {
  const client = { query: async () => undefined, release: () => undefined };
  return { connect: async () => client } as never;
}

test('cart schemas accept only product and bounded quantity fields', () => {
  assert.deepEqual(cartItemSchema.parse({ productId: '00000000-0000-0000-0000-000000000001', quantity: 2 }), { productId: '00000000-0000-0000-0000-000000000001', quantity: 2 });
  assert.throws(() => cartItemSchema.parse({ productId: '00000000-0000-0000-0000-000000000001', quantity: 0 }));
  assert.throws(() => cartItemSchema.parse({ productId: '00000000-0000-0000-0000-000000000001', quantity: 2, price: '1.00' }));
  assert.throws(() => cartQuantitySchema.parse({ quantity: 101 }));
});

test('cart service returns server-projected price and totals rather than client totals', async () => {
  const cart = { id: 'cart-id', items: [{ productId: 'product-id', name: 'Book', seller: { username: 'seller', displayName: 'Seller', avatarUrl: null }, quantity: 2, unitPrice: '10.25', currency: 'USD', lineTotal: '20.50', available: true, media: [] }], subtotal: '20.50', currency: 'USD' };
  const repository = { get: async () => cart, readCart: async () => cart, addItem: async () => 'cart-id', updateItem: async () => 'cart-id', removeItem: async () => true, clear: async () => true } as unknown as CartRepository;
  const service = new CartService(fakePool(), repository);
  const result = await service.addItem('buyer-id', { productId: '00000000-0000-0000-0000-000000000001', quantity: 2 });
  assert.equal(result.cart.subtotal, '20.50');
  assert.equal(result.cart.items[0]!.unitPrice, '10.25');
});

test('cart product and currency failures map to safe application errors', async () => {
  const repository = { addItem: async () => { throw new Error('MIXED_CURRENCIES'); } } as unknown as CartRepository;
  const service = new CartService(fakePool(), repository);
  await assert.rejects(() => service.addItem('buyer-id', { productId: '00000000-0000-0000-0000-000000000001', quantity: 1 }), (error: unknown) => error instanceof AppError && error.code === 'BAD_REQUEST');
});

test('order creation is idempotent and returns the server order projection', async () => {
  const order = { id: 'order-id', status: 'pending', currency: 'USD', subtotal: '20.50', total: '20.50', createdAt: '2026-01-01T00:00:00Z', items: [{ id: 'item-id', productId: 'product-id', sellerId: 'seller-id', productName: 'Book', quantity: 2, unitPrice: '10.25', lineTotal: '20.50', currency: 'USD' }] };
  const repository = { createFromCart: async () => 'order-id', get: async () => order, list: async () => ({ items: [order], total: 1 }) } as unknown as OrderRepository;
  const service = new OrderService(fakePool(), repository);
  const result = await service.create('buyer-id', 'idempotency-key-123');
  assert.equal(result.order.total, '20.50');
  assert.equal(result.order.items[0]!.unitPrice, '10.25');
});

test('empty-cart, inventory, and idempotency failures are mapped consistently', async () => {
  for (const [message, code] of [['EMPTY_CART', 'BAD_REQUEST'], ['INSUFFICIENT_INVENTORY', 'CONFLICT'], ['IDEMPOTENCY_KEY_CONFLICT', 'CONFLICT']] as const) {
    const repository = { createFromCart: async () => { throw new Error(message); } } as unknown as OrderRepository;
    const service = new OrderService(fakePool(), repository);
    await assert.rejects(() => service.create('buyer-id', 'idempotency-key-123'), (error: unknown) => error instanceof AppError && error.code === code);
  }
});
