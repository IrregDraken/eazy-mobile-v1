ALTER TABLE comments ADD COLUMN parent_id uuid REFERENCES comments(id) ON DELETE CASCADE;
CREATE INDEX comments_parent_created_idx ON comments(parent_id, created_at, id);
CREATE TABLE comment_likes (
  comment_id uuid NOT NULL REFERENCES comments(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (comment_id, user_id)
);
CREATE INDEX comment_likes_user_idx ON comment_likes(user_id, created_at DESC);
CREATE TABLE post_tags (
  post_id uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tagged_by uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);
CREATE INDEX post_tags_user_idx ON post_tags(user_id, created_at DESC);
ALTER TABLE posts ADD COLUMN is_pinned boolean NOT NULL DEFAULT false;
ALTER TABLE posts ADD COLUMN pinned_at timestamptz;
CREATE INDEX posts_author_pinned_idx ON posts(author_id, is_pinned DESC, pinned_at DESC, created_at DESC);
CREATE TABLE profile_highlights (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(title) BETWEEN 1 AND 40),
  cover_storage_key text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE profile_highlight_stories (
  highlight_id uuid NOT NULL REFERENCES profile_highlights(id) ON DELETE CASCADE,
  story_id uuid NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
  position integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (highlight_id, story_id)
);
CREATE INDEX profile_highlights_owner_idx ON profile_highlights(owner_id, created_at);
