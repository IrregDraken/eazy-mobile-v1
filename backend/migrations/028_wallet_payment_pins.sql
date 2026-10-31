CREATE TABLE public.wallet_payment_pins (
  user_id uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  pin_hash text NOT NULL,
  failed_attempts integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  locked_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER wallet_payment_pins_set_updated_at
BEFORE UPDATE ON public.wallet_payment_pins
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.wallet_payment_pins ENABLE ROW LEVEL SECURITY;

CREATE POLICY wallet_payment_pins_backend_only
ON public.wallet_payment_pins
AS RESTRICTIVE
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

COMMENT ON TABLE public.wallet_payment_pins IS
  'Backend-only payment PIN hashes and lockout state. Raw PINs are never stored.';
