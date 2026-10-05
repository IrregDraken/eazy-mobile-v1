ALTER TABLE order_items ADD COLUMN product_name text;
CREATE INDEX order_items_order_idx ON order_items (order_id, id);
