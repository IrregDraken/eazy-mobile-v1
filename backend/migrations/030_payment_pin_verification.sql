-- Four-digit PINs are the current format. Existing six-digit hashes remain verifiable
-- so current users can migrate by changing their PIN after this deployment.
ALTER TABLE wallet_payment_pins
  ADD COLUMN IF NOT EXISTS pin_length SMALLINT NOT NULL DEFAULT 6
  CHECK (pin_length IN (4, 6));

CREATE TABLE IF NOT EXISTS payment_pin_verification_challenges (
  id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  code_digest CHAR(64) NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts SMALLINT NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts SMALLINT NOT NULL DEFAULT 5 CHECK (max_attempts BETWEEN 1 AND 10),
  consumed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_pin_verification_challenges_user_created_idx
  ON payment_pin_verification_challenges (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS payment_pin_verification_challenges_expiry_idx
  ON payment_pin_verification_challenges (expires_at);
