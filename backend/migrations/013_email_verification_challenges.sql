CREATE TABLE email_verification_challenges (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  code_digest text NOT NULL,
  expires_at timestamptz NOT NULL,
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  max_attempts integer NOT NULL DEFAULT 5 CHECK (max_attempts BETWEEN 1 AND 10),
  verified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX email_verification_challenges_email_created_idx
  ON email_verification_challenges (email, created_at DESC);
CREATE INDEX email_verification_challenges_expiry_idx
  ON email_verification_challenges (expires_at);
ALTER TABLE email_verification_challenges ENABLE ROW LEVEL SECURITY;
CREATE POLICY deny_direct_client_access ON email_verification_challenges AS RESTRICTIVE
  FOR ALL TO anon, authenticated USING (false) WITH CHECK (false);
COMMENT ON TABLE email_verification_challenges IS 'Server-side hashed email OTP challenges; codes are never stored in plaintext.';
