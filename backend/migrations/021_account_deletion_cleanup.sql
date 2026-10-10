-- Durable, server-owned account-deletion progress. External provider work is intentionally
-- performed after the database transaction and can be retried without reopening the account.
CREATE TABLE account_deletion_jobs (
  user_id uuid PRIMARY KEY REFERENCES users(id),
  firebase_uid text NOT NULL,
  identity_deleted boolean NOT NULL DEFAULT false,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'complete', 'failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE account_deletion_media (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES account_deletion_jobs(user_id) ON DELETE CASCADE,
  storage_key text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'deleted', 'failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, storage_key),
  CHECK (storage_key !~ '(^/|\.\.|\\)')
);
CREATE INDEX account_deletion_media_pending_idx
  ON account_deletion_media (user_id, status, id);
CREATE TRIGGER account_deletion_jobs_updated_at
  BEFORE UPDATE ON account_deletion_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER account_deletion_media_updated_at
  BEFORE UPDATE ON account_deletion_media FOR EACH ROW EXECUTE FUNCTION set_updated_at();
ALTER TABLE account_deletion_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_deletion_media ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'account_deletion_jobs' AND policyname = 'deny_direct_client_access') THEN
    CREATE POLICY deny_direct_client_access ON account_deletion_jobs AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'account_deletion_media' AND policyname = 'deny_direct_client_access') THEN
    CREATE POLICY deny_direct_client_access ON account_deletion_media AS RESTRICTIVE FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
  END IF;
END $$;
