import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';
import { ORDER_ESCROW_AUTO_RELEASE_DAYS } from './constants.js';

export interface OrderProjection {
  id: string;
  status: string;
  currency: string;
  subtotal: string;
  total: string;
  deliveryTotal?: string;
  fulfillments?: unknown[];
  timeline?: unknown[];
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
    for (const sellerId of sellerIds) {
      const choice = selected.get(sellerId)!;
      const settingsResult = await client.query<{
        delivery_enabled: boolean; pickup_enabled: boolean; delivery_fee_amount: string;
        currency: string; pickup_instructions: string | null;
      }>(
        'SELECT delivery_enabled, pickup_enabled, delivery_fee_amount::text, trim(currency) AS currency, pickup_instructions FROM seller_delivery_settings WHERE seller_id = $1',
        [sellerId]
      );
      const settings = settingsResult.rows[0] ?? {
        delivery_enabled: false, pickup_enabled: true, delivery_fee_amount: '0.00',
        currency: 'NGN', pickup_instructions: null
      };
      if (settings.currency !== currency) throw new Error('DELIVERY_CURRENCY_MISMATCH');

      let addressSnapshot: Record<string, string | null> | null = null;
      let deliveryFee = '0.00';
      if (choice.method === 'delivery') {
        if (!settings.delivery_enabled) throw new Error('DELIVERY_UNAVAILABLE');
        if (!choice.addressId) throw new Error('DELIVERY_ADDRESS_REQUIRED');
        const address = await client.query<{
          recipient_name: string; phone: string; state: string; city: string;
          area: string; address_line: string; landmark: string | null;
        }>(
          'SELECT recipient_name, phone, state, city, area, address_line, landmark FROM delivery_addresses WHERE id = $1 AND user_id = $2',
          [choice.addressId, buyerId]
        );
        const row = address.rows[0];
        if (!row) throw new Error('DELIVERY_ADDRESS_NOT_FOUND');
        addressSnapshot = {
          recipientName: row.recipient_name, phone: row.phone, state: row.state,
          city: row.city, area: row.area, addressLine: row.address_line, landmark: row.landmark
        };
        deliveryFee = settings.delivery_fee_amount;
      } else {
        if (!settings.pickup_enabled) throw new Error('PICKUP_UNAVAILABLE');
        if (choice.addressId) throw new Error('PICKUP_ADDRESS_NOT_ALLOWED');
      }

      const fulfillment = await client.query<{ id: string }>(
        `INSERT INTO order_fulfillments
          (order_id, seller_id, delivery_method, delivery_fee_amount, address_snapshot, pickup_instructions)
         VALUES ($1,$2,$3,$4::numeric,$5::jsonb,$6) RETURNING id`,
        [orderId, sellerId, choice.method, deliveryFee,
          addressSnapshot ? JSON.stringify(addressSnapshot) : null, settings.pickup_instructions]
      );
      await client.query(
        "INSERT INTO order_events (order_id, fulfillment_id, actor_user_id, event_type, description) VALUES ($1,$2,$3,'order_created','Order placed and awaiting payment')",
        [orderId, fulfillment.rows[0]!.id, buyerId]
      );
    }

    await client.query(
      `UPDATE orders o
       SET subtotal_amount = totals.subtotal,
           delivery_total_amount = totals.delivery_total,
           total_amount = totals.subtotal + totals.delivery_total,
           updated_at = now()
       FROM (
         SELECT
           (SELECT COALESCE(sum(line_total_amount), 0)::numeric FROM order_items WHERE order_id = $1) AS subtotal,
           (SELECT COALESCE(sum(delivery_fee_amount), 0)::numeric FROM order_fulfillments WHERE order_id = $1) AS delivery_total
       ) totals
       WHERE o.id = $1`,
      [orderId]
    );
    await client.query('DELETE FROM cart_items WHERE cart_id = $1', [cartId]);
    await client.query("UPDATE carts SET status = 'checked_out', updated_at = now() WHERE id = $1", [cartId]);
    return orderId;
  }

  async get(buyerId: string, orderId: string): Promise<OrderProjection | null> {
    const order = await this.pool.query<{
      id: string; status: string; currency: string; subtotal: string;
      deliveryTotal: string; total: string; createdAt: string;
    }>(
      `SELECT id, status, trim(currency) AS currency,
        subtotal_amount::text AS subtotal, delivery_total_amount::text AS "deliveryTotal",
        total_amount::text AS total, created_at AS "createdAt"
       FROM orders WHERE id = $1 AND buyer_id = $2 LIMIT 1`,
      [orderId, buyerId]
    );
    if (!order.rows[0]) return null;
    const items = await this.pool.query<OrderProjection['items'][number]>(
      `SELECT oi.id, oi.product_id AS "productId", oi.seller_id AS "sellerId",
        COALESCE(oi.product_name, p.name) AS "productName", oi.quantity,
        oi.unit_price_amount::text AS "unitPrice", oi.line_total_amount::text AS "lineTotal",
        trim(oi.currency) AS currency
       FROM order_items oi JOIN products p ON p.id = oi.product_id
       WHERE oi.order_id = $1 ORDER BY oi.id ASC`,
      [orderId]
    );
    const fulfillments = await this.pool.query(
      `SELECT f.id, f.seller_id AS "sellerId", seller.username AS "sellerUsername",
        seller.display_name AS "sellerDisplayName", f.delivery_method AS "deliveryMethod",
        f.status, f.delivery_fee_amount::text AS "deliveryFee", f.address_snapshot AS "deliveryAddress",
        f.pickup_instructions AS "pickupInstructions", f.accepted_at AS "acceptedAt",
        f.shipped_at AS "shippedAt", f.delivered_at AS "deliveredAt",
        f.release_after AS "releaseAfter",
        EXISTS (SELECT 1 FROM order_disputes d WHERE d.fulfillment_id = f.id AND d.status IN ('open','reviewing')) AS "hasOpenDispute"
       FROM order_fulfillments f JOIN profiles seller ON seller.user_id = f.seller_id
       WHERE f.order_id = $1 ORDER BY f.created_at ASC, f.id ASC`,
      [orderId]
    );
    const timeline = await this.pool.query(
      `SELECT id, event_type AS type, description, created_at AS "createdAt"
       FROM order_events WHERE order_id = $1 ORDER BY created_at ASC, id ASC`,
      [orderId]
    );
    return { ...order.rows[0], items: items.rows, fulfillments: fulfillments.rows, timeline: timeline.rows };
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
  async listSellerOrders(sellerId: string, page: number, limit: number) {
    const count = await this.pool.query<{ count: string }>(
      'SELECT count(DISTINCT f.order_id)::text AS count FROM order_fulfillments f JOIN orders o ON o.id = f.order_id WHERE f.seller_id = $1 AND o.status <> \'pending\'',
      [sellerId]
    );
    const result = await this.pool.query(
      `SELECT f.id AS "fulfillmentId", f.order_id AS "orderId", f.status,
        f.delivery_method AS "deliveryMethod", f.delivery_fee_amount::text AS "deliveryFee",
        f.created_at AS "createdAt", f.accepted_at AS "acceptedAt",
        f.shipped_at AS "shippedAt", f.delivered_at AS "deliveredAt",
        CASE WHEN f.accepted_at IS NULL THEN NULL ELSE f.address_snapshot END AS "deliveryAddress",
        f.pickup_instructions AS "pickupInstructions",
        o.status AS "orderStatus", o.currency, o.total_amount::text AS "orderTotal",
        buyer.username AS "buyerUsername", buyer.display_name AS "buyerDisplayName",
        COALESCE(items.rows, '[]'::json) AS items
       FROM order_fulfillments f
       JOIN orders o ON o.id = f.order_id
       JOIN profiles buyer ON buyer.user_id = o.buyer_id
       LEFT JOIN LATERAL (
         SELECT json_agg(json_build_object(
           'productId', oi.product_id, 'productName', oi.product_name,
           'quantity', oi.quantity, 'unitPrice', oi.unit_price_amount::text,
           'lineTotal', oi.line_total_amount::text
         ) ORDER BY oi.id) AS rows
         FROM order_items oi WHERE oi.order_id = f.order_id AND oi.seller_id = f.seller_id
       ) items ON true
       WHERE f.seller_id = $1 AND o.status <> 'pending'
       ORDER BY f.created_at DESC, f.id DESC LIMIT $2 OFFSET $3`,
      [sellerId, limit, (page - 1) * limit]
    );
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async updateSellerFulfillment(
    client: DbClient,
    sellerId: string,
    orderId: string,
    fulfillmentId: string,
    action: 'accept' | 'reject' | 'ship' | 'deliver',
    reason?: string
  ) {
    const selected = await client.query<{
      id: string; status: string; order_status: string; buyer_id: string; seller_id: string;
      delivery_method: string; order_currency: string;
    }>(
      `SELECT f.id, f.status, o.status AS order_status, o.buyer_id, f.seller_id,
        f.delivery_method, o.currency AS order_currency
       FROM order_fulfillments f JOIN orders o ON o.id = f.order_id
       WHERE f.id = $1 AND f.order_id = $2 AND f.seller_id = $3
       FOR UPDATE OF f, o`,
      [fulfillmentId, orderId, sellerId]
    );
    const row = selected.rows[0];
    if (!row) return { error: 'NOT_FOUND' as const };
    if (row.order_status !== 'paid' && row.order_status !== 'accepted' && row.order_status !== 'processing' && row.order_status !== 'shipped' && row.order_status !== 'delivered') {
      return { error: 'ORDER_NOT_PAID' as const };
    }
    const next = action === 'accept' ? 'accepted' : action === 'reject' ? 'cancelled' :
      action === 'ship' ? 'shipped' : 'delivered';
    const allowed =
      (action === 'accept' || action === 'reject') ? row.status === 'pending' :
      action === 'ship' ? row.status === 'accepted' :
      row.status === 'shipped';
    if (!allowed) return { error: 'INVALID_TRANSITION' as const };

    if (action === 'reject' && (!reason || reason.trim().length < 5 || reason.trim().length > 500)) {
      return { error: 'REJECTION_REASON_REQUIRED' as const };
    }
    const timestampColumn = action === 'accept' ? 'accepted_at' : action === 'ship' ? 'shipped_at' : action === 'deliver' ? 'delivered_at' : null;
    const releaseClause = action === 'deliver' ? ', release_after = now() + ($3::int * interval \'1 day\')' : '';
    const timestampClause = timestampColumn ? `, ${timestampColumn} = now()` : '';
    await client.query(
      `UPDATE order_fulfillments SET status = $2${timestampClause}${releaseClause}, updated_at = now() WHERE id = $1`,
      [fulfillmentId, next]
    );
    await client.query(
      `INSERT INTO order_events (order_id, fulfillment_id, actor_user_id, event_type, description, metadata)
       VALUES ($1,$2,$3,$4,$5,$6::jsonb)`,
      [orderId, fulfillmentId, sellerId, `seller_${action}`,
        action === 'reject' ? `Seller rejected the order: ${reason!.trim()}` :
        action === 'accept' ? 'Seller accepted the order' :
        action === 'ship' ? 'Seller marked the order as shipped' : 'Seller marked the order as delivered',
        JSON.stringify(action === 'reject' ? { reason: reason!.trim() } : {})]
    );
    const aggregate = await client.query<{ status: string }>(
      `SELECT CASE
        WHEN bool_and(status IN ('completed','cancelled')) THEN CASE WHEN bool_or(status = 'completed') THEN 'completed' ELSE 'cancelled' END
        WHEN bool_or(status = 'disputed') THEN 'disputed'
        WHEN bool_and(status IN ('delivered','completed','cancelled')) THEN 'delivered'
        WHEN bool_or(status = 'shipped') THEN 'shipped'
        WHEN bool_or(status = 'accepted') THEN 'accepted'
        ELSE 'paid' END AS status
       FROM order_fulfillments WHERE order_id = $1`,
      [orderId]
    );
    await client.query('UPDATE orders SET status = $2, updated_at = now() WHERE id = $1', [orderId, aggregate.rows[0]!.status]);
    await client.query(
      `INSERT INTO notifications (user_id, actor_user_id, type, target_type, target_id, title, body, deep_link)
       VALUES ($1,$2,'order','order',$3,$4,$5,$6)`,
      [row.buyer_id, sellerId, orderId,
        action === 'accept' ? 'Order accepted' : action === 'reject' ? 'Order rejected' : action === 'ship' ? 'Order shipped' : 'Order delivered',
        action === 'reject' ? `The seller rejected your order: ${reason!.trim()}` :
        action === 'accept' ? 'The seller accepted your order.' :
        action === 'ship' ? 'Your order has been marked as shipped.' : 'Your order has been marked as delivered.',
        `eazy://orders/${orderId}`]
    );
    return { error: null as null, status: next };
  }

  async confirmReceived(client: DbClient, buyerId: string, orderId: string, fulfillmentId: string) {
    const selected = await client.query<{ id: string; seller_id: string; status: string; currency: string; buyer_id: string }>(
      `SELECT f.id, f.seller_id, f.status, trim(o.currency) AS currency, o.buyer_id
       FROM order_fulfillments f JOIN orders o ON o.id = f.order_id
       WHERE f.id = $1 AND f.order_id = $2 AND o.buyer_id = $3
       FOR UPDATE OF f, o`,
      [fulfillmentId, orderId, buyerId]
    );
    const row = selected.rows[0];
    if (!row) return { error: 'NOT_FOUND' as const };
    if (row.status === 'completed') return { error: null as null, alreadyCompleted: true };
    if (row.status === 'disputed') return { error: 'DISPUTED' as const };
    if (row.status !== 'delivered') return { error: 'NOT_DELIVERED' as const };
    const hold = await client.query<{ amount: string }>(
      "SELECT amount::numeric(20,2)::text AS amount FROM seller_payable_ledger WHERE fulfillment_id = $1 AND entry_type = 'hold' FOR UPDATE",
      [fulfillmentId]
    );
    if (!hold.rows[0]) return { error: 'ESCROW_HOLD_NOT_FOUND' as const };
    await client.query(
      `INSERT INTO seller_payable_ledger
        (order_id, fulfillment_id, seller_id, entry_type, amount, currency, idempotency_key)
       VALUES ($1,$2,$3,'release',$4::numeric,$5,'order-release:' || $2::text)
       ON CONFLICT (fulfillment_id, entry_type) DO NOTHING`,
      [orderId, fulfillmentId, row.seller_id, hold.rows[0].amount, row.currency]
    );
    await client.query(
      "UPDATE order_fulfillments SET status = 'completed', release_after = NULL, updated_at = now() WHERE id = $1",
      [fulfillmentId]
    );
    await client.query(
      "INSERT INTO order_events (order_id, fulfillment_id, actor_user_id, event_type, description) VALUES ($1,$2,$3,'buyer_confirmed','Buyer confirmed receipt. Seller payable funds released.')",
      [orderId, fulfillmentId, buyerId]
    );
    const aggregate = await client.query<{ status: string }>(
      `SELECT CASE
        WHEN bool_and(status IN ('completed','cancelled')) THEN CASE WHEN bool_or(status = 'completed') THEN 'completed' ELSE 'cancelled' END
        WHEN bool_or(status = 'disputed') THEN 'disputed'
        WHEN bool_and(status IN ('delivered','completed','cancelled')) THEN 'delivered'
        WHEN bool_or(status = 'shipped') THEN 'shipped'
        WHEN bool_or(status = 'accepted') THEN 'accepted'
        ELSE 'paid' END AS status
       FROM order_fulfillments WHERE order_id = $1`,
      [orderId]
    );
    await client.query('UPDATE orders SET status = $2, updated_at = now() WHERE id = $1', [orderId, aggregate.rows[0]!.status]);
    await client.query(
      `INSERT INTO notifications (user_id, actor_user_id, type, target_type, target_id, title, body, deep_link)
       VALUES ($1,$2,'order','order',$3,'Order completed','The buyer confirmed receipt. Your payable balance has been released.',$4)`,
      [row.seller_id, buyerId, orderId, `eazy://orders/${orderId}`]
    );
    return { error: null as null, alreadyCompleted: false };
  }

  async createDispute(
    client: DbClient,
    buyerId: string,
    orderId: string,
    fulfillmentId: string,
    input: { reason: string; description: string; photoStorageKeys: string[] }
  ) {
    const selected = await client.query<{ seller_id: string; status: string }>(
      `SELECT f.seller_id, f.status FROM order_fulfillments f
       JOIN orders o ON o.id = f.order_id
       WHERE f.id = $1 AND f.order_id = $2 AND o.buyer_id = $3
       FOR UPDATE OF f, o`,
      [fulfillmentId, orderId, buyerId]
    );
    const row = selected.rows[0];
    if (!row) return { error: 'NOT_FOUND' as const };
    if (!['accepted','shipped','delivered'].includes(row.status)) return { error: 'INVALID_DISPUTE_STATE' as const };
    const dispute = await client.query<{ id: string }>(
      `INSERT INTO order_disputes (order_id, fulfillment_id, buyer_id, seller_id, reason, description, photo_storage_keys)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
      [orderId, fulfillmentId, buyerId, row.seller_id, input.reason, input.description.trim(), input.photoStorageKeys]
    );
    await client.query(
      "UPDATE order_fulfillments SET status = 'disputed', release_after = NULL, updated_at = now() WHERE id = $1",
      [fulfillmentId]
    );
    await client.query("UPDATE orders SET status = 'disputed', updated_at = now() WHERE id = $1", [orderId]);
    await client.query(
      "INSERT INTO order_events (order_id, fulfillment_id, actor_user_id, event_type, description) VALUES ($1,$2,$3,'dispute_opened','Buyer reported a problem. Seller payable funds remain on hold.')",
      [orderId, fulfillmentId, buyerId]
    );
    await client.query(
      `INSERT INTO notifications (user_id, actor_user_id, type, target_type, target_id, title, body, deep_link)
       VALUES ($1,$2,'order','order',$3,'Order dispute opened','The buyer reported a problem with this order. Seller funds remain held.',$4)`,
      [row.seller_id, buyerId, orderId, `eazy://orders/${orderId}`]
    );
    return { error: null as null, disputeId: dispute.rows[0]!.id };
  }

  async releaseDueEscrow(client: DbClient, limit: number) {
    const due = await client.query<{
      id: string; order_id: string; seller_id: string; buyer_id: string;
      currency: string; amount: string;
    }>(
      `SELECT f.id, f.order_id, f.seller_id, o.buyer_id, trim(o.currency) AS currency,
        hold.amount::numeric(20,2)::text AS amount
       FROM order_fulfillments f
       JOIN orders o ON o.id = f.order_id
       JOIN seller_payable_ledger hold ON hold.fulfillment_id = f.id AND hold.entry_type = 'hold'
       WHERE f.status = 'delivered' AND f.release_after <= now()
         AND NOT EXISTS (
           SELECT 1 FROM order_disputes d
           WHERE d.fulfillment_id = f.id AND d.status IN ('open','reviewing')
         )
       ORDER BY f.release_after ASC, f.id ASC
       LIMIT $1 FOR UPDATE OF f SKIP LOCKED`,
      [limit]
    );
    for (const row of due.rows) {
      await client.query(
        `INSERT INTO seller_payable_ledger
          (order_id, fulfillment_id, seller_id, entry_type, amount, currency, idempotency_key)
         VALUES ($1,$2,$3,'release',$4::numeric,$5,'order-release:' || $2::text)
         ON CONFLICT (fulfillment_id, entry_type) DO NOTHING`,
        [row.order_id, row.id, row.seller_id, row.amount, row.currency]
      );
      await client.query(
        "UPDATE order_fulfillments SET status = 'completed', release_after = NULL, updated_at = now() WHERE id = $1 AND status = 'delivered'",
        [row.id]
      );
      await client.query(
        "INSERT INTO order_events (order_id, fulfillment_id, actor_user_id, event_type, description) VALUES ($1,$2,NULL,'escrow_auto_released','The seven-day delivery confirmation window elapsed. Seller payable funds were released.')",
        [row.order_id, row.id]
      );
      await client.query(
        `INSERT INTO notifications (user_id, actor_user_id, type, target_type, target_id, title, body, deep_link)
         VALUES ($1,NULL,'order','order',$2,'Order completed','Your order was automatically completed after the delivery confirmation period.',$3),
                ($4,NULL,'order','order',$2,'Payable released','The buyer did not report a problem during the delivery confirmation period. Your payable funds were released.',$3)`,
        [row.buyer_id, row.order_id, 'eazy://orders/' + row.order_id, row.seller_id]
      );
      await client.query(
        `UPDATE orders o SET status = aggregate.status, updated_at = now()
         FROM (
           SELECT CASE
             WHEN bool_and(status IN ('completed','cancelled')) THEN CASE WHEN bool_or(status = 'completed') THEN 'completed' ELSE 'cancelled' END
             WHEN bool_or(status = 'disputed') THEN 'disputed'
             WHEN bool_and(status IN ('delivered','completed','cancelled')) THEN 'delivered'
             WHEN bool_or(status = 'shipped') THEN 'shipped'
             WHEN bool_or(status = 'accepted') THEN 'accepted'
             ELSE 'paid' END AS status
           FROM order_fulfillments WHERE order_id = $1
         ) aggregate
         WHERE o.id = $1`,
        [row.order_id]
      );
    }
    return due.rows.length;
  }

}
