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

  async listAddresses(userId: string) {
    const result = await this.pool.query(
      `SELECT id, label, recipient_name AS "recipientName", phone, state, city, area,
        address_line AS "addressLine", landmark, is_default AS "isDefault",
        created_at AS "createdAt"
       FROM delivery_addresses WHERE user_id = $1 ORDER BY is_default DESC, created_at DESC, id DESC`,
      [userId]
    );
    return result.rows;
  }

  async createAddress(client: DbClient, userId: string, input: {
    label: string; recipientName: string; phone: string; state: string; city: string;
    area: string; addressLine: string; landmark?: string | null; isDefault?: boolean;
  }) {
    const count = await client.query<{ count: string }>(
      'SELECT count(*)::text AS count FROM delivery_addresses WHERE user_id = $1',
      [userId]
    );
    const isDefault = input.isDefault === true || Number(count.rows[0]?.count ?? 0) === 0;
    if (isDefault) await client.query('UPDATE delivery_addresses SET is_default = false WHERE user_id = $1', [userId]);
    const result = await client.query(
      `INSERT INTO delivery_addresses
        (user_id, label, recipient_name, phone, state, city, area, address_line, landmark, is_default)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       RETURNING id, label, recipient_name AS "recipientName", phone, state, city, area,
        address_line AS "addressLine", landmark, is_default AS "isDefault"`,
      [userId, input.label, input.recipientName, input.phone, input.state, input.city, input.area,
        input.addressLine, input.landmark ?? null, isDefault]
    );
    return result.rows[0];
  }

  async updateAddress(client: DbClient, userId: string, addressId: string, input: {
    label: string; recipientName: string; phone: string; state: string; city: string;
    area: string; addressLine: string; landmark?: string | null; isDefault?: boolean;
  }) {
    if (input.isDefault === true) await client.query('UPDATE delivery_addresses SET is_default = false WHERE user_id = $1', [userId]);
    const result = await client.query(
      `UPDATE delivery_addresses SET label=$3, recipient_name=$4, phone=$5, state=$6, city=$7,
        area=$8, address_line=$9, landmark=$10, is_default=$11, updated_at=now()
       WHERE user_id=$1 AND id=$2
       RETURNING id, label, recipient_name AS "recipientName", phone, state, city, area,
        address_line AS "addressLine", landmark, is_default AS "isDefault"`,
      [userId, addressId, input.label, input.recipientName, input.phone, input.state, input.city,
        input.area, input.addressLine, input.landmark ?? null, input.isDefault === true]
    );
    return result.rows[0] ?? null;
  }

  async deleteAddress(client: DbClient, userId: string, addressId: string) {
    const result = await client.query<{ is_default: boolean }>(
      'DELETE FROM delivery_addresses WHERE user_id = $1 AND id = $2 RETURNING is_default',
      [userId, addressId]
    );
    if (!result.rowCount) return false;
    if (result.rows[0]?.is_default) {
      const next = await client.query<{ id: string }>(
        'SELECT id FROM delivery_addresses WHERE user_id = $1 ORDER BY created_at ASC, id ASC LIMIT 1',
        [userId]
      );
      if (next.rows[0]) await client.query('UPDATE delivery_addresses SET is_default = true WHERE id = $1', [next.rows[0].id]);
    }
    return true;
  }

  async createFromCart(client: DbClient, buyerId: string, idempotencyKey: string, fulfillments: { sellerId: string; method: 'delivery' | 'pickup'; addressId?: string }[]): Promise<string> {
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

    const sellerIds = [...new Set(items.rows.map(item => item.seller_id))].sort();
    const selected = new Map(fulfillments.map(choice => [choice.sellerId, choice]));
    if (selected.size !== fulfillments.length || selected.size !== sellerIds.length ||
        sellerIds.some(id => !selected.has(id))) {
      throw new Error('FULFILLMENT_SELECTION_REQUIRED');
    }

    const order = await client.query<{ id: string }>(
      "INSERT INTO orders (buyer_id, status, currency, subtotal_amount, delivery_total_amount, total_amount, idempotency_key) VALUES ($1, 'pending', $2, 0, 0, 0, $3) RETURNING id",
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
