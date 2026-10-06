-- Harden database helper functions against search_path hijacking and keep migration metadata
-- inaccessible to direct PostgREST clients.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_wallet_ledger_debit()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  current_balance numeric(20,2);
BEGIN
  IF NEW.direction = 'debit' THEN
    PERFORM 1 FROM public.wallets WHERE id = NEW.wallet_id FOR UPDATE;
    SELECT COALESCE(sum(CASE WHEN direction = 'credit' THEN amount ELSE -amount END), 0)
      INTO current_balance FROM public.ledger_entries WHERE wallet_id = NEW.wallet_id;
    IF current_balance < NEW.amount THEN
      RAISE EXCEPTION 'Insufficient wallet funds' USING ERRCODE = '23514', CONSTRAINT = 'ledger_entries_no_negative_balance';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.require_balanced_internal_transfer()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE debit_count integer; credit_count integer; total_count integer;
BEGIN
  IF NEW.status = 'succeeded' AND OLD.status = 'pending' AND NEW.type IN ('transfer','qr_payment') THEN
    SELECT count(*), count(*) FILTER (WHERE wallet_id = NEW.wallet_id AND direction = 'debit'),
           count(*) FILTER (WHERE wallet_id = NEW.counterparty_wallet_id AND direction = 'credit')
      INTO total_count, debit_count, credit_count
      FROM public.ledger_entries
      WHERE transaction_id = NEW.id AND amount = NEW.amount AND currency = NEW.currency;
    IF total_count <> 2 OR debit_count <> 1 OR credit_count <> 1 THEN
      RAISE EXCEPTION 'Unbalanced internal transfer ledger' USING ERRCODE = '23514', CONSTRAINT = 'transactions_balanced_internal_ledger';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_ledger_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'Ledger entries are immutable' USING ERRCODE = '23514', CONSTRAINT = 'ledger_entries_immutable';
END;
$$;

ALTER TABLE public.schema_migrations ENABLE ROW LEVEL SECURITY;

CREATE POLICY schema_migrations_backend_only
ON public.schema_migrations
AS RESTRICTIVE
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

COMMENT ON TABLE public.schema_migrations IS 'Backend migration bookkeeping. Direct Supabase client access is denied by RLS.';
