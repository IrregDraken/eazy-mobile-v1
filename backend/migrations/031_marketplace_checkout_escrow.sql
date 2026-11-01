ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending','paid','accepted','processing','shipped','delivered','completed','disputed','cancelled','refunded'));

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS delivery_total_kobo BIGINT NOT NULL DEFAULT 0
  CHECK (delivery_total_kobo >= 0);

CREATE TABLE IF NOT EXISTS delivery_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  label VARCHAR(40) NOT NULL,
  recipient_name VARCHAR(120) NOT NULL,
  phone VARCHAR(30) NOT NULL,
  state VARCHAR(80) NOT NULL,
  city VARCHAR(80) NOT NULL,
  area VARCHAR(120) NOT NULL,
  address_line VARCHAR(240) NOT NULL,
  landmark VARCHAR(160),
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS delivery_addresses_user_created_idx ON delivery_addresses (user_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS delivery_addresses_one_default_idx ON delivery_addresses (user_id) WHERE is_default = true;

CREATE TABLE IF NOT EXISTS seller_delivery_settings (
  seller_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  delivery_enabled BOOLEAN NOT NULL DEFAULT false,
  pickup_enabled BOOLEAN NOT NULL DEFAULT true,
  delivery_fee_kobo BIGINT NOT NULL DEFAULT 0 CHECK (delivery_fee_kobo >= 0),
  currency CHAR(3) NOT NULL DEFAULT 'NGN',
  pickup_instructions TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (delivery_enabled OR pickup_enabled)
);

CREATE TABLE IF NOT EXISTS order_fulfillments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  seller_id UUID NOT NULL REFERENCES users(id),
  delivery_method TEXT NOT NULL CHECK (delivery_method IN ('delivery','pickup')),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','shipped','delivered','completed','disputed','cancelled')),
  delivery_fee_kobo BIGINT NOT NULL DEFAULT 0 CHECK (delivery_fee_kobo >= 0),
  address_snapshot JSONB,
  pickup_instructions TEXT,
  accepted_at TIMESTAMPTZ,
  shipped_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  release_after TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (order_id, seller_id),
  CHECK ((delivery_method = 'delivery' AND address_snapshot IS NOT NULL) OR (delivery_method = 'pickup' AND address_snapshot IS NULL))
);
CREATE INDEX IF NOT EXISTS order_fulfillments_seller_status_idx ON order_fulfillments (seller_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS order_fulfillments_release_after_idx ON order_fulfillments (release_after) WHERE status = 'delivered';

CREATE TABLE IF NOT EXISTS order_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  fulfillment_id UUID REFERENCES order_fulfillments(id) ON DELETE CASCADE,
  actor_user_id UUID REFERENCES users(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL,
  description TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS order_events_timeline_idx ON order_events (order_id, created_at ASC, id ASC);

CREATE TABLE IF NOT EXISTS seller_payable_ledger (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id),
  fulfillment_id UUID NOT NULL REFERENCES order_fulfillments(id),
  seller_id UUID NOT NULL REFERENCES users(id),
  entry_type TEXT NOT NULL CHECK (entry_type IN ('hold','release')),
  amount_kobo BIGINT NOT NULL CHECK (amount_kobo > 0),
  currency CHAR(3) NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (fulfillment_id, entry_type)
);
CREATE INDEX IF NOT EXISTS seller_payable_ledger_seller_created_idx ON seller_payable_ledger (seller_id, created_at DESC);

CREATE TABLE IF NOT EXISTS order_disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  fulfillment_id UUID NOT NULL REFERENCES order_fulfillments(id) ON DELETE CASCADE,
  buyer_id UUID NOT NULL REFERENCES users(id),
  seller_id UUID NOT NULL REFERENCES users(id),
  reason TEXT NOT NULL CHECK (reason IN ('not_received','damaged','wrong_item','missing_items','other')),
  description TEXT NOT NULL CHECK (length(trim(description)) BETWEEN 10 AND 2000),
  photo_storage_keys TEXT[] NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewing','resolved','dismissed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (fulfillment_id) 
);
CREATE INDEX IF NOT EXISTS order_disputes_seller_status_idx ON order_disputes (seller_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS order_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  order_item_id UUID NOT NULL UNIQUE REFERENCES order_items(id) ON DELETE CASCADE,
  buyer_id UUID NOT NULL REFERENCES users(id),
  seller_id UUID NOT NULL REFERENCES users(id),
  product_id UUID NOT NULL REFERENCES products(id),
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review_text TEXT NOT NULL CHECK (length(trim(review_text)) BETWEEN 1 AND 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS order_reviews_product_created_idx ON order_reviews (product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS order_reviews_seller_created_idx ON order_reviews (seller_id, created_at DESC);
