-- Apply the same server-only access boundary to social tables introduced
-- after 004_rls_policies.sql. Eazy's backend connects with the PostgreSQL
-- backend role; anon/authenticated Supabase clients must not access these
-- records directly.
DO $$
DECLARE
  table_name text;
  policy_name text := 'deny_direct_client_access';
BEGIN
  FOREACH table_name IN ARRAY ARRAY[
    'stories',
    'story_views',
    'comment_likes',
    'post_tags',
    'profile_highlights',
    'profile_highlight_stories'
  ]
  LOOP
    IF to_regclass(format('public.%I', table_name)) IS NULL THEN
      RAISE EXCEPTION 'Required social table public.% is missing', table_name;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);

    IF NOT EXISTS (
      SELECT 1
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = table_name
        AND policyname = policy_name
    ) THEN
      EXECUTE format(
        'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false)',
        policy_name,
        table_name
      );
    END IF;
  END LOOP;
END $$;
