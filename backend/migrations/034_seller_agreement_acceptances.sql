CREATE TABLE IF NOT EXISTS seller_agreement_acceptances (
  seller_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  agreement_version VARCHAR(100) NOT NULL,
  accepted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (seller_id, agreement_version)
);
