-- Keep the RLS-enforcement event trigger operational while removing
-- its SECURITY DEFINER function from the public PostgREST RPC surface.
-- The event trigger was created by postgres and remains owned by postgres.
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated, service_role;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_event_trigger et
    WHERE et.evtname = 'ensure_rls'
      AND et.evtfoid = 'public.rls_auto_enable()'::regprocedure
      AND et.evtenabled = 'O'
  ) THEN
    RAISE EXCEPTION 'Expected enabled event trigger ensure_rls is missing or not bound to public.rls_auto_enable()';
  END IF;
END
$$;
