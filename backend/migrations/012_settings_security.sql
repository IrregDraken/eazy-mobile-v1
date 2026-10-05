CREATE TABLE user_settings (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  language_code text NOT NULL DEFAULT 'en' CHECK (length(language_code) BETWEEN 2 AND 35),
  theme text NOT NULL DEFAULT 'system' CHECK (theme IN ('system','light','dark')),
  notify_follows boolean NOT NULL DEFAULT true,
  notify_likes boolean NOT NULL DEFAULT true,
  notify_comments boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE sessions
  ADD COLUMN last_activity_at timestamptz,
  ADD COLUMN ip_address inet,
  ADD COLUMN user_agent text;

CREATE UNIQUE INDEX sessions_user_provider_session_unique
  ON sessions (user_id, provider_session_id)
  WHERE provider_session_id IS NOT NULL;

CREATE INDEX sessions_user_created_idx
  ON sessions (user_id, created_at DESC, id DESC);

CREATE TRIGGER user_settings_updated_at
  BEFORE UPDATE ON user_settings
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

ALTER TABLE user_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON user_settings AS RESTRICTIVE
  FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);

COMMENT ON TABLE user_settings IS 'Explicit user-owned language, appearance, and currently enforced notification preferences.';
COMMENT ON COLUMN sessions.provider_session_id IS 'Opaque SHA-256 identifier derived from verified Firebase UID and auth_time; never a raw credential.';
COMMENT ON COLUMN sessions.user_agent IS 'Bounded request User-Agent metadata captured for the Eazy session list.';
COMMENT ON COLUMN sessions.ip_address IS 'Last-seen request IP captured for the Eazy session list.';
COMMENT ON COLUMN sessions.last_activity_at IS 'Updated when the Firebase-authenticated Eazy session is used.';
