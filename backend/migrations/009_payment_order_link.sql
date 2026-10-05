-- Financial records remain attached to server-owned wallets and orders.
ALTER TABLE transactions
  ADD COLUMN order_id uuid REFERENCES orders(id),
  ADD COLUMN counterparty_wallet_id uuid REFERENCES wallets(id),
  ADD CONSTRAINT transactions_wallets_distinct_check
    CHECK (counterparty_wallet_id IS NULL OR wallet_id IS NULL OR counterparty_wallet_id <> wallet_id),
  ADD CONSTRAINT transactions_order_purchase_check
    CHECK (order_id IS NULL OR type = 'purchase'),
  ADD CONSTRAINT transactions_internal_counterparty_check
    CHECK ((type IN ('transfer','qr_payment') AND counterparty_wallet_id IS NOT NULL) OR (type NOT IN ('transfer','qr_payment') AND counterparty_wallet_id IS NULL)),
  ADD CONSTRAINT transactions_internal_amount_positive_check
    CHECK (type NOT IN ('transfer','qr_payment','deposit') OR amount > 0);

-- Order purchases must exactly match the authenticated order owner and total.
ALTER TABLE orders
  ADD CONSTRAINT orders_id_buyer_currency_total_key UNIQUE (id, buyer_id, currency, total_amount);
ALTER TABLE transactions
  ADD CONSTRAINT transactions_order_authority_fk
    FOREIGN KEY (order_id, user_id, currency, amount)
    REFERENCES orders (id, buyer_id, currency, total_amount);

-- A ledger movement cannot be detached from its authoritative transaction.
ALTER TABLE ledger_entries ALTER COLUMN transaction_id SET NOT NULL;

-- Composite keys let PostgreSQL enforce currency and user/wallet consistency.
ALTER TABLE wallets
  ADD CONSTRAINT wallets_id_currency_key UNIQUE (id, currency),
  ADD CONSTRAINT wallets_id_user_key UNIQUE (id, user_id);

ALTER TABLE transactions
  ADD CONSTRAINT transactions_id_amount_currency_key UNIQUE (id, amount, currency),
  ADD CONSTRAINT transactions_wallet_currency_fk FOREIGN KEY (wallet_id, currency) REFERENCES wallets(id, currency),
  ADD CONSTRAINT transactions_wallet_user_fk FOREIGN KEY (wallet_id, user_id) REFERENCES wallets(id, user_id),
  ADD CONSTRAINT transactions_counterparty_currency_fk FOREIGN KEY (counterparty_wallet_id, currency) REFERENCES wallets(id, currency);

ALTER TABLE ledger_entries
  ADD CONSTRAINT ledger_entries_wallet_currency_fk FOREIGN KEY (wallet_id, currency) REFERENCES wallets(id, currency),
  ADD CONSTRAINT ledger_entries_transaction_amount_currency_fk FOREIGN KEY (transaction_id, amount, currency) REFERENCES transactions(id, amount, currency);

ALTER TABLE payment_attempts
  ADD CONSTRAINT payment_attempts_transaction_amount_currency_fk FOREIGN KEY (transaction_id, amount, currency) REFERENCES transactions(id, amount, currency);

-- Existing idempotent entry keys plus row-level guards prevent duplicate transfer legs.
CREATE UNIQUE INDEX ledger_entries_one_direction_per_wallet_transaction
  ON ledger_entries (transaction_id, wallet_id, direction);
CREATE INDEX transactions_order_id_idx ON transactions (order_id) WHERE order_id IS NOT NULL;
CREATE UNIQUE INDEX transactions_one_pending_purchase_per_order
  ON transactions (order_id)
  WHERE order_id IS NOT NULL AND type = 'purchase' AND status = 'pending';
CREATE UNIQUE INDEX transactions_one_successful_purchase_per_order
  ON transactions (order_id)
  WHERE order_id IS NOT NULL AND type = 'purchase' AND status = 'succeeded';

-- Serialize every wallet debit at the wallet row and prevent overdrafts even if
-- a future trusted backend operation omits its own balance check.
CREATE FUNCTION guard_wallet_ledger_debit() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
  current_balance numeric(20,2);
BEGIN
  IF NEW.direction = 'debit' THEN
    PERFORM 1 FROM wallets WHERE id = NEW.wallet_id FOR UPDATE;
    SELECT COALESCE(sum(CASE WHEN direction = 'credit' THEN amount ELSE -amount END), 0)
      INTO current_balance FROM ledger_entries WHERE wallet_id = NEW.wallet_id;
    IF current_balance < NEW.amount THEN
      RAISE EXCEPTION 'Insufficient wallet funds' USING ERRCODE = '23514', CONSTRAINT = 'ledger_entries_no_negative_balance';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER ledger_entries_no_negative_balance
  BEFORE INSERT ON ledger_entries
  FOR EACH ROW EXECUTE FUNCTION guard_wallet_ledger_debit();

-- Internal transfer transactions cannot become successful without exactly one
-- matching debit and credit leg to their locked sender/recipient wallets.
CREATE FUNCTION require_balanced_internal_transfer() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE debit_count integer; credit_count integer; total_count integer;
BEGIN
  IF NEW.status = 'succeeded' AND OLD.status = 'pending' AND NEW.type IN ('transfer','qr_payment') THEN
    SELECT count(*), count(*) FILTER (WHERE wallet_id = NEW.wallet_id AND direction = 'debit'),
           count(*) FILTER (WHERE wallet_id = NEW.counterparty_wallet_id AND direction = 'credit')
      INTO total_count, debit_count, credit_count
      FROM ledger_entries WHERE transaction_id = NEW.id AND amount = NEW.amount AND currency = NEW.currency;
    IF total_count <> 2 OR debit_count <> 1 OR credit_count <> 1 THEN
      RAISE EXCEPTION 'Unbalanced internal transfer ledger' USING ERRCODE = '23514', CONSTRAINT = 'transactions_balanced_internal_ledger';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER transactions_balanced_internal_ledger
  BEFORE UPDATE OF status ON transactions
  FOR EACH ROW EXECUTE FUNCTION require_balanced_internal_transfer();

CREATE FUNCTION reject_ledger_mutation() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'Ledger entries are immutable' USING ERRCODE = '23514', CONSTRAINT = 'ledger_entries_immutable';
END;
$$;
CREATE TRIGGER ledger_entries_immutable
  BEFORE UPDATE OR DELETE ON ledger_entries
  FOR EACH ROW EXECUTE FUNCTION reject_ledger_mutation();
