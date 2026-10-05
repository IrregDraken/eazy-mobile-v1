CREATE INDEX products_status_created_idx ON products (status, created_at DESC, id DESC);
CREATE INDEX products_name_search_idx ON products (lower(name));
CREATE INDEX products_description_search_idx ON products (lower(description));
CREATE INDEX categories_created_idx ON categories (created_at ASC, id ASC);
CREATE INDEX inventory_availability_idx ON inventory (product_id, available_quantity, reserved_quantity);
