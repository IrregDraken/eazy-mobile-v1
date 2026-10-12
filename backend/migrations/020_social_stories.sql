CREATE TABLE stories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  storage_key text NOT NULL CHECK (length(storage_key) BETWEEN 1 AND 1024),
  media_type text NOT NULL CHECK (media_type IN ('image','video')),
  caption text NOT NULL DEFAULT '' CHECK (length(caption) <= 500),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  CHECK (expires_at > created_at)
);
CREATE INDEX stories_author_active_idx ON stories(author_id, expires_at DESC);
CREATE INDEX stories_active_idx ON stories(expires_at DESC);
CREATE TABLE story_views (
  story_id uuid NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  viewer_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  viewed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (story_id, viewer_id)
);
CREATE INDEX story_views_viewer_idx ON story_views(viewer_id, viewed_at DESC);
