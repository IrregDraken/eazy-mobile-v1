CREATE TABLE wallet_virtual_accounts (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  wallet_id uuid NOT NULL UNIQUE REFERENCES wallets(id) ON DELETE CASCADE,
  provider text NOT NULL,
  provider_customer_code text,
  provider_account_id text,
  account_number text,
  account_name text,
  bank_name text,
  bank_slug text,
  currency char(3) NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','failed','suspended')),
  consented_at timestamptz,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX wallet_virtual_accounts_provider_customer_idx
  ON wallet_virtual_accounts(provider, provider_customer_code)
  WHERE provider_customer_code IS NOT NULL;

CREATE UNIQUE INDEX wallet_virtual_accounts_provider_account_idx
  ON wallet_virtual_accounts(provider, provider_account_id)
  WHERE provider_account_id IS NOT NULL;

CREATE UNIQUE INDEX wallet_virtual_accounts_account_number_idx
  ON wallet_virtual_accounts(account_number)
  WHERE account_number IS NOT NULL;

CREATE INDEX wallet_virtual_accounts_status_idx
  ON wallet_virtual_accounts(status);