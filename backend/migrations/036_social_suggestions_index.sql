CREATE INDEX IF NOT EXISTS follows_followee_created_idx
  ON public.follows (followee_id, created_at DESC);
