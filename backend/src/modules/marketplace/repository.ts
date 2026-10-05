import type { Pool } from 'pg';
import type { DbClient } from '../../database/client.js';

export interface ProductMediaInput { storageKey: string; position: number; }
export interface ProductFilters { q?: string; categoryId?: string; sellerId?: string; minPrice?: string; maxPrice?: string; currency?: string; availability?: 'in_stock' | 'out_of_stock'; status?: 'active' | 'sold_out'; sort: 'newest' | 'price_asc' | 'price_desc'; page: number; limit: number; viewerId?: string; }
export interface ProductProjection {
  id: string;
  name: string;
  description: string | null;
  priceAmount: string;
  currency: string;
  status: string;
  createdAt: string;
  category: { id: string; name: string; slug: string } | null;
  seller: { username: string; displayName: string; avatarUrl: string | null };
  media: { storageKey: string; position: number }[];
  availability: { inStock: boolean; availableQuantity?: number };
}

const productSelect = `p.id, p.name, p.description, p.price_amount::text AS "priceAmount", trim(p.currency) AS currency, p.status, p.created_at AS "createdAt",
  CASE WHEN c.id IS NULL THEN NULL ELSE json_build_object('id', c.id, 'name', c.name, 'slug', c.slug) END AS category,
  json_build_object('username', seller.username, 'displayName', seller.display_name, 'avatarUrl', seller.avatar_url) AS seller,
  COALESCE((SELECT json_agg(json_build_object('storageKey', pm.storage_key, 'position', pm.position) ORDER BY pm.position) FROM product_media pm WHERE pm.product_id = p.id), '[]'::json) AS media,
  json_build_object('inStock', (COALESCE(i.available_quantity, 0) - COALESCE(i.reserved_quantity, 0) > 0)) AS availability`;

export class MarketplaceRepository {
  constructor(private readonly pool: Pool) {}

  async categories(page: number, limit: number): Promise<{ items: { id: string; name: string; slug: string }[]; total: number }> {
    const count = await this.pool.query<{ count: string }>('SELECT count(*)::text AS count FROM categories');
    const result = await this.pool.query<{ id: string; name: string; slug: string }>('SELECT id, name, slug FROM categories ORDER BY name ASC, id ASC LIMIT $1 OFFSET $2', [limit, (page - 1) * limit]);
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async products(filters: ProductFilters): Promise<{ items: ProductProjection[]; total: number }> {
    const values: unknown[] = [];
    const add = (value: unknown) => { values.push(value); return `$${values.length}`; };
    const conditions = ["p.status IN ('active', 'sold_out')", 'seller_user.status = \'active\''];
    if (filters.q) {
      const pattern = `${filters.q.toLowerCase()}%`;
      const q = add(pattern);
      conditions.push(`(lower(p.name) LIKE ${q} OR lower(COALESCE(p.description, '')) LIKE ${q} OR lower(c.name) LIKE ${q} OR lower(c.slug) LIKE ${q})`);
    }
    if (filters.categoryId) conditions.push(`p.category_id = ${add(filters.categoryId)}`);
    if (filters.sellerId) conditions.push(`p.seller_id = ${add(filters.sellerId)}`);
    if (filters.minPrice) conditions.push(`p.price_amount >= ${add(filters.minPrice)}::numeric`);
    if (filters.maxPrice) conditions.push(`p.price_amount <= ${add(filters.maxPrice)}::numeric`);
    if (filters.currency) conditions.push(`upper(trim(p.currency)) = ${add(filters.currency)}`);
    if (filters.status) conditions.push(`p.status = ${add(filters.status)}`);
    if (filters.availability === 'in_stock') conditions.push('(COALESCE(i.available_quantity, 0) - COALESCE(i.reserved_quantity, 0) > 0)');
    if (filters.availability === 'out_of_stock') conditions.push('(COALESCE(i.available_quantity, 0) - COALESCE(i.reserved_quantity, 0) <= 0)');
    if (filters.viewerId) {
      const viewer = add(filters.viewerId);
      conditions.push(`NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = ${viewer} AND b.blocked_id = p.seller_id) OR (b.blocker_id = p.seller_id AND b.blocked_id = ${viewer}))`);
    }
    const where = conditions.join(' AND ');
    const countValues = [...values];
    const count = await this.pool.query<{ count: string }>(`SELECT count(*)::text AS count FROM products p JOIN users seller_user ON seller_user.id = p.seller_id LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN inventory i ON i.product_id = p.id WHERE ${where}`, countValues);
    const limit = add(filters.limit);
    const offset = add((filters.page - 1) * filters.limit);
    const order = filters.sort === 'price_asc' ? 'p.price_amount ASC, p.id ASC' : filters.sort === 'price_desc' ? 'p.price_amount DESC, p.id ASC' : 'p.created_at DESC, p.id DESC';
    const result = await this.pool.query<ProductProjection>(`SELECT ${productSelect} FROM products p JOIN users seller_user ON seller_user.id = p.seller_id LEFT JOIN profiles seller ON seller.user_id = p.seller_id LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN inventory i ON i.product_id = p.id WHERE ${where} ORDER BY ${order} LIMIT ${limit} OFFSET ${offset}`, values);
    return { items: result.rows, total: Number(count.rows[0]?.count ?? 0) };
  }

  async getById(productId: string, viewerId?: string): Promise<ProductProjection | null> {
    const result = await this.pool.query<ProductProjection>(
      `SELECT ${productSelect} FROM products p JOIN users seller_user ON seller_user.id = p.seller_id JOIN profiles seller ON seller.user_id = p.seller_id LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN inventory i ON i.product_id = p.id
       WHERE p.id = $1 AND seller_user.status = 'active'
         AND ($2::uuid IS NOT NULL AND p.seller_id = $2 OR p.status IN ('active', 'sold_out'))
         AND ($2::uuid IS NULL OR NOT EXISTS (SELECT 1 FROM blocks b WHERE (b.blocker_id = $2 AND b.blocked_id = p.seller_id) OR (b.blocker_id = p.seller_id AND b.blocked_id = $2)))
       LIMIT 1`,
      [productId, viewerId ?? null]
    );
    return result.rows[0] ?? null;
  }

  async create(client: DbClient, sellerId: string, input: { name: string; description?: string; categoryId?: string; priceAmount: string; currency: string; status: string; media: ProductMediaInput[]; availableQuantity: number }): Promise<string> {
    const result = await client.query<{ id: string }>('INSERT INTO products (seller_id, category_id, name, description, price_amount, currency, status) VALUES ($1, $2, $3, $4, $5::numeric, $6, $7) RETURNING id', [sellerId, input.categoryId ?? null, input.name, input.description ?? null, input.priceAmount, input.currency, input.status]);
    const productId = result.rows[0]!.id;
    await client.query('INSERT INTO inventory (product_id, available_quantity, reserved_quantity) VALUES ($1, $2, 0)', [productId, input.availableQuantity]);
    for (const media of input.media) await client.query('INSERT INTO product_media (product_id, storage_key, position) VALUES ($1, $2, $3)', [productId, media.storageKey, media.position]);
    return productId;
  }

  async update(client: DbClient, productId: string, sellerId: string, input: { name?: string; description?: string | null; categoryId?: string | null; priceAmount?: string; currency?: string; status?: string }): Promise<boolean> {
    const fields: string[] = [];
    const values: unknown[] = [];
    for (const [column, value] of Object.entries({ name: input.name, description: input.description, category_id: input.categoryId, price_amount: input.priceAmount, currency: input.currency, status: input.status })) {
      if (value !== undefined) { values.push(value); fields.push(`${column} = $${values.length}${column === 'price_amount' ? '::numeric' : ''}`); }
    }
    if (!fields.length) return false;
    values.push(productId, sellerId);
    const result = await client.query(`UPDATE products SET ${fields.join(', ')}, updated_at = now() WHERE id = $${values.length - 1} AND seller_id = $${values.length} RETURNING id`, values);
    return Boolean(result.rowCount);
  }

  async updateInventory(client: DbClient, productId: string, sellerId: string, availableQuantity: number): Promise<boolean> {
    const result = await client.query(
      `UPDATE inventory i SET available_quantity = $1, updated_at = now()
       FROM products p WHERE i.product_id = p.id AND i.product_id = $2 AND p.seller_id = $3 RETURNING i.product_id`,
      [availableQuantity, productId, sellerId]
    );
    return Boolean(result.rowCount);
  }
}
