ALTER TABLE users
  ADD COLUMN IF NOT EXISTS email_verified_at timestamptz;

CREATE INDEX IF NOT EXISTS users_email_verified_idx
  ON users (email_verified_at)
  WHERE email_verified_at IS NOT NULL;
