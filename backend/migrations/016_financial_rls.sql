ALTER TABLE public.bank_transfer_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_virtual_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY deny_direct_client_access
ON public.bank_transfer_details
AS RESTRICTIVE
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

CREATE POLICY deny_direct_client_access
ON public.wallet_virtual_accounts
AS RESTRICTIVE
FOR ALL
TO anon, authenticated
USING (false)
WITH CHECK (false);

COMMENT ON TABLE public.bank_transfer_details IS 'Backend-only financial settlement metadata. Direct Supabase client access is denied by RLS.';
COMMENT ON TABLE public.wallet_virtual_accounts IS 'Backend-only virtual bank account metadata. Direct Supabase client access is denied by RLS.';