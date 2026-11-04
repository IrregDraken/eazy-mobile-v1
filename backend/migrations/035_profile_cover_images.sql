ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS cover_url text;

COMMENT ON COLUMN public.profiles.cover_url IS
  'Private Eazy media storage path or approved HTTPS cover image URL for the profile banner.';
