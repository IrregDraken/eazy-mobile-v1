ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS location text;

COMMENT ON COLUMN public.profiles.location IS
  'Optional user-entered public location shown on the Eazy profile.';
