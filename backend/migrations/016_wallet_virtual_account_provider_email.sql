ALTER TABLE wallet_virtual_accounts
  ADD COLUMN IF NOT EXISTS provider_email text;

CREATE INDEX IF NOT EXISTS wallet_virtual_accounts_provider_email_idx
  ON wallet_virtual_accounts(provider, provider_email)
  WHERE provider_email IS NOT NULL;
