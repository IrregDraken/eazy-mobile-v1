CREATE TABLE bank_transfer_details (
  transaction_id uuid PRIMARY KEY REFERENCES transactions(id) ON DELETE CASCADE,
  bank_code text NOT NULL,
  bank_name text,
  account_name text NOT NULL,
  account_fingerprint text NOT NULL,
  recipient_code text,
  provider_reference text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX bank_transfer_details_provider_reference_idx
  ON bank_transfer_details(provider_reference)
  WHERE provider_reference IS NOT NULL;

CREATE INDEX bank_transfer_details_recipient_idx
  ON bank_transfer_details(recipient_code)
  WHERE recipient_code IS NOT NULL;

CREATE INDEX transactions_pending_withdrawals_idx
  ON transactions(status, type, updated_at)
  WHERE type = 'withdrawal' AND status = 'pending';