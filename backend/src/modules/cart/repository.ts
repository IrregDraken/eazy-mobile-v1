import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';

export interface CartItemInput { productId: string; quantity: number; }
export interface CartProjection {
  id: string;
  items: {
    productId: string;
    name: string;
    seller: { username: string; displayName: string; avatarUrl: string | null };
    quantity: number;
    unitPrice: string;
    currency: string;
    lineTotal: string;
    available: boolean;
    media: { storageKey: string; position: number }[];
  }[];
  subtotal: string;
  currency: string | null;
}

export class CartRepository {
  constructor(private readonly pool: Pool) {}

  async activeCart(client: Pool | DbClient, buyerId: string): Promise<{ id: string } | null> {
    const result = await client.query<{ id: string }>("SELECT id FROM carts WHERE buyer_id = $1 AND status = 'active' LIMIT 1", [buyerId]);
    return result.rows[0] ?? null;
  }

  async ensureActiveCart(client: DbClient, buyerId: string): Promise<string> {
    const existing = await this.activeCart(client, buyerId);
    if (existing) return existing.id;
    await client.query("INSERT INTO carts (buyer_id, status) VALUES ($1, 'active') ON CONFLICT (buyer_id) WHERE status = 'active' DO NOTHING", [buyerId]);
    const cart = await this.activeCart(client, buyerId);
    if (!cart) throw new Error('Cart could not be created');
    return cart.id;
  }

  async get(buyerId: string): Promise<CartProjection> {
    return this.readCart(this.pool, await this.ensureForRead(buyerId));
  }

  private async ensureForRead(buyerId: string): Promise<string> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const id = await this.ensureActiveCart(client, buyerId);
      await client.query('COMMIT');
      return id;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally { client.release(); }
  }

  async readCart(client: Pool | DbClient, cartId: string): Promise<CartProjection> {
    const result = await client.query<CartProjection['items'][number] & { cartId: string; subtotal: string; cartCurrency: string | null; currencyCount: number }>(
      `SELECT c.id AS "cartId", ci.product_id AS "productId", p.name,
        json_build_object('username', seller.username, 'displayName', seller.display_name, 'avatarUrl', seller.avatar_url) AS seller,
        ci.quantity, p.price_amount::text AS "unitPrice", trim(p.currency) AS currency,
        (p.price_amount * ci.quantity)::text AS "lineTotal",
        (p.status = 'active' AND COALESCE(i.available_quantity, 0) - COALESCE(i.reserved_quantity, 0) >= ci.quantity) AS available,
        COALESCE((SELECT json_agg(json_build_object('storageKey', pm.storage_key, 'position', pm.position) ORDER BY pm.position) FROM product_media pm WHERE pm.product_id = p.id), '[]'::json) AS media,
        (SELECT COALESCE(sum(p2.price_amount * ci2.quantity), 0)::text FROM cart_items ci2 JOIN products p2 ON p2.id = ci2.product_id WHERE ci2.cart_id = c.id) AS subtotal,
        (SELECT min(trim(p3.currency)) FROM cart_items ci3 JOIN products p3 ON p3.id = ci3.product_id WHERE ci3.cart_id = c.id) AS "cartCurrency",
        (SELECT count(DISTINCT trim(p4.currency))::int FROM cart_items ci4 JOIN products p4 ON p4.id = ci4.product_id WHERE ci4.cart_id = c.id) AS "currencyCount"
       FROM carts c JOIN cart_items ci ON ci.cart_id = c.id JOIN products p ON p.id = ci.product_id
       JOIN users seller_user ON seller_user.id = p.seller_id LEFT JOIN profiles seller ON seller.user_id = p.seller_id
       LEFT JOIN inventory i ON i.product_id = p.id
       WHERE c.id = $1 AND c.status = 'active' ORDER BY ci.created_at ASC, ci.product_id ASC`,
      [cartId]
    );
    const first = result.rows[0];
    if (first?.currencyCount && first.currencyCount > 1) throw new Error('MIXED_CURRENCIES');
    const items = result.rows.map(({ cartId: _cartId, subtotal: _subtotal, cartCurrency: _cartCurrency, currencyCount: _currencyCount, ...item }) => item);
    return { id: first?.cartId ?? cartId, items, subtotal: first?.subtotal ?? '0.00', currency: first?.cartCurrency ?? null };
  }

  async addItem(client: DbClient, buyerId: string, input: CartItemInput): Promise<string> {
    const cartId = await this.ensureActiveCart(client, buyerId);
    const product = await client.query<{ price: string; currency: string; existing: number; available: number }>(
      `SELECT p.price_amount::text AS price, trim(p.currency) AS currency,
        COALESCE((SELECT quantity FROM cart_items WHERE cart_id = $1 AND product_id = p.id), 0) AS existing,
        COALESCE(i.available_quantity, 0) - COALESCE(i.reserved_quantity, 0) AS available
       FROM products p JOIN inventory i ON i.product_id = p.id
       JOIN users u ON u.id = p.seller_id
       WHERE p.id = $2 AND p.status = 'active' AND u.status = 'active'
       FOR UPDATE OF p, i`, [cartId, input.productId]);
    const row = product.rows[0];
    if (!row) throw new Error('PRODUCT_UNAVAILABLE');
    const quantity = row.existing + input.quantity;
    if (quantity > row.available) throw new Error('INSUFFICIENT_INVENTORY');
    const currencies = await client.query<{ currency: string }>('SELECT DISTINCT trim(p.currency) AS currency FROM cart_items ci JOIN products p ON p.id = ci.product_id WHERE ci.cart_id = $1', [cartId]);
    if (currencies.rows.some(item => item.currency !== row.currency)) throw new Error('MIXED_CURRENCIES');
    await client.query(
      `INSERT INTO cart_items (cart_id, product_id, quantity, unit_price_amount, currency) VALUES ($1, $2, $3, $4::numeric, $5)
       ON CONFLICT (cart_id, product_id) DO UPDATE SET quantity = EXCLUDED.quantity, unit_price_amount = EXCLUDED.unit_price_amount, currency = EXCLUDED.currency`,
      [cartId, input.productId, quantity, row.price, row.currency]
    );
    await client.query('UPDATE carts SET updated_at = now() WHERE id = $1 AND buyer_id = $2 AND status = \'active\'', [cartId, buyerId]);
    return cartId;
  }

  async updateItem(client: DbClient, buyerId: string, productId: string, quantity: number): Promise<string | null> {
    const cart = await this.activeCart(client, buyerId);
    if (!cart) return null;
    const result = await client.query<{ price: string; currency: string; available: number }>(
      `SELECT p.price_amount::text AS price, trim(p.currency) AS currency, i.available_quantity - i.reserved_quantity AS available
       FROM cart_items ci JOIN products p ON p.id = ci.product_id JOIN inventory i ON i.product_id = p.id
       JOIN users u ON u.id = p.seller_id WHERE ci.cart_id = $1 AND ci.product_id = $2 AND p.status = 'active' AND u.status = 'active' FOR UPDATE OF p, i`,
      [cart.id, productId]
    );
    const row = result.rows[0];
    if (!row) return null;
    if (quantity > row.available) throw new Error('INSUFFICIENT_INVENTORY');
    await client.query('UPDATE cart_items SET quantity = $1, unit_price_amount = $2::numeric, currency = $3 WHERE cart_id = $4 AND product_id = $5', [quantity, row.price, row.currency, cart.id, productId]);
    await client.query('UPDATE carts SET updated_at = now() WHERE id = $1', [cart.id]);
    return cart.id;
  }

  async removeItem(client: DbClient, buyerId: string, productId: string): Promise<boolean> {
    const result = await client.query('DELETE FROM cart_items ci USING carts c WHERE ci.cart_id = c.id AND c.buyer_id = $1 AND c.status = \'active\' AND ci.product_id = $2 RETURNING ci.product_id', [buyerId, productId]);
    return Boolean(result.rowCount);
  }

  async clear(client: DbClient, buyerId: string): Promise<boolean> {
    const result = await client.query("UPDATE carts SET status = 'abandoned', updated_at = now() WHERE buyer_id = $1 AND status = 'active' RETURNING id", [buyerId]);
    return Boolean(result.rowCount);
  }
}
