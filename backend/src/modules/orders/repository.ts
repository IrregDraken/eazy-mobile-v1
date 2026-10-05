import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';

export interface OrderProjection {
  id: string;
  status: string;
  currency: string;
  subtotal: string;
  total: string;
  createdAt: string;
  items: {
    id: string;
    productId: string;
    sellerId: string;
    productName: string;
    quantity: number;
    unitPrice: string;
    lineTotal: string;
    currency: string;
  }[];
}

export class OrderRepository {
  constructor(private readonly pool: Pool) {}

  async createFromCart(client: DbClient, buyerId: string, idempotencyKey: string): Promise<string> {
    const existing = await client.query<{ id: string; buyer_id: string }>('SELECT id, buyer_id FROM orders WHERE idempotency_key = $1 FOR UPDATE', [idempotencyKey]);
    if (existing.rows[0]) {
      if (existing.rows[0].buyer_id !== buyerId) throw new Error('IDEMPOTENCY_KEY_CONFLICT');
      return existing.rows[0].id;
    }

    const cart = await client.query<{ id: string }>("SELECT id FROM carts WHERE buyer_id = $1 AND status = 'active' FOR UPDATE", [buyerId]);
    if (!cart.rows[0]) throw new Error('EMPTY_CART');
    const cartId = cart.rows[0].id;
    const items = await client.query<{ product_id: string; quantity: number; price: string; currency: string; seller_id: string; product_name: string }>(
      `SELECT ci.product_id, ci.quantity, p.price_amount::text AS price, trim(p.currency) AS currency, p.seller_id, p.name AS product_name
       FROM cart_items ci JOIN products p ON p.id = ci.product_id JOIN users seller ON seller.id = p.seller_id
       JOIN inventory i ON i.product_id = p.id
       WHERE ci.cart_id = $1 AND p.status = 'active' AND seller.status = 'active'
       ORDER BY ci.product_id ASC FOR UPDATE OF p, i`,
      [cartId]
    );
    if (!items.rows.length) throw new Error('EMPTY_CART');
    const currencies = new Set(items.rows.map(item => item.currency));
    if (currencies.size !== 1) throw new Error('MIXED_CURRENCIES');
    const currency = items.rows[0]!.currency;

    const order = await client.query<{ id: string }>(
      "INSERT INTO orders (buyer_id, status, currency, subtotal_amount, total_amount, idempotency_key) VALUES ($1, 'pending', $2, 0, 0, $3) RETURNING id",
      [buyerId, currency, idempotencyKey]
    );
    const orderId = order.rows[0]!.id;
    for (const item of items.rows) {
      const reserved = await client.query(
        `UPDATE inventory SET reserved_quantity = reserved_quantity + $1, updated_at = now()
         WHERE product_id = $2 AND available_quantity - reserved_quantity >= $1 RETURNING product_id`,
        [item.quantity, item.product_id]
      );
      if (!reserved.rowCount) throw new Error('INSUFFICIENT_INVENTORY');
      await client.query(
        `INSERT INTO order_items (order_id, product_id, seller_id, product_name, quantity, unit_price_amount, line_total_amount, currency)
         VALUES ($1, $2, $3, $4, $5, $6::numeric, ($6::numeric * $5), $7)`,
        [orderId, item.product_id, item.seller_id, item.product_name, item.quantity, item.price, item.currency]
      );
    }
    await client.query(
      `UPDATE orders o SET subtotal_amount = totals.total_amount, total_amount = totals.total_amount, updated_at = now()
       FROM (SELECT COALESCE(sum(line_total_amount), 0)::numeric AS total_amount FROM order_items WHERE order_id = $1) totals
       WHERE o.id = $1`,
      [orderId]
    );
    await client.query('DELETE FROM cart_items WHERE cart_id = $1', [cartId]);
    await client.query("UPDATE carts SET status = 'checked_out', updated_at = now() WHERE id = $1", [cartId]);
    return orderId;
  }

  async get(buyerId: string, orderId: string): Promise<OrderProjection | null> {
    const order = await this.pool.query<{ id: string; status: string; currency: string; subtotal: string; total: string; createdAt: string }>(
      `SELECT id, status, trim(currency) AS currency, subtotal_amount::text AS subtotal, total_amount::text AS total, created_at AS "createdAt"
       FROM orders WHERE id = $1 AND buyer_id = $2 LIMIT 1`, [orderId, buyerId]
    );
    if (!order.rows[0]) return null;
    const items = await this.pool.query<OrderProjection['items'][number]>(
      `SELECT oi.id, oi.product_id AS "productId", oi.seller_id AS "sellerId", COALESCE(oi.product_name, p.name) AS "productName", oi.quantity,
        oi.unit_price_amount::text AS "unitPrice", oi.line_total_amount::text AS "lineTotal", trim(oi.currency) AS currency
       FROM order_items oi JOIN products p ON p.id = oi.product_id WHERE oi.order_id = $1 ORDER BY oi.id ASC`, [orderId]
    );
    return { ...order.rows[0], items: items.rows };
  }

  async list(buyerId: string, page: number, limit: number): Promise<{ items: OrderProjection[]; total: number }> {
    const count = await this.pool.query<{ count: string }>('SELECT count(*)::text AS count FROM orders WHERE buyer_id = $1', [buyerId]);
    const orders = await this.pool.query<{ id: string; status: string; currency: string; subtotal: string; total: string; createdAt: string }>(
      `SELECT id, status, trim(currency) AS currency, subtotal_amount::text AS subtotal, total_amount::text AS total, created_at AS "createdAt"
       FROM orders WHERE buyer_id = $1 ORDER BY created_at DESC, id DESC LIMIT $2 OFFSET $3`, [buyerId, limit, (page - 1) * limit]
    );
    const items = await Promise.all(orders.rows.map(order => this.get(buyerId, order.id)));
    return { items: items.filter((item): item is OrderProjection => item !== null), total: Number(count.rows[0]?.count ?? 0) };
  }
}
