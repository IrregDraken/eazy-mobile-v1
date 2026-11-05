CREATE TABLE IF NOT EXISTS seller_stores (
  seller_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  store_name VARCHAR(100) NOT NULL,
  slug VARCHAR(60) NOT NULL UNIQUE,
  description VARCHAR(1500) NOT NULL DEFAULT '',
  support_phone VARCHAR(30),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (slug ~ '^[a-z0-9][a-z0-9-]{2,59}$')
);
CREATE INDEX IF NOT EXISTS seller_stores_status_name_idx ON seller_stores (status, store_name);
