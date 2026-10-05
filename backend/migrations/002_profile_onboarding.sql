ALTER TABLE profiles
  ADD COLUMN first_name text,
  ADD COLUMN last_name text,
  ADD COLUMN date_of_birth date,
  ADD COLUMN onboarding_status text NOT NULL DEFAULT 'profile_incomplete'
    CHECK (onboarding_status IN ('profile_incomplete', 'onboarding_complete'));

COMMENT ON COLUMN profiles.avatar_url IS 'Storage-provider object URL or path; binary data is not stored in PostgreSQL.';
COMMENT ON COLUMN profiles.date_of_birth IS 'Calendar date only; no timezone conversion is applied.';
