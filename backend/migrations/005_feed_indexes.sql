CREATE INDEX posts_feed_created_idx ON posts (created_at DESC, id DESC) WHERE status = 'published';
CREATE INDEX post_media_post_position_idx ON post_media (post_id, position);
CREATE INDEX likes_post_idx ON likes (post_id);
CREATE INDEX saves_post_idx ON saves (post_id);
CREATE INDEX comments_post_visible_idx ON comments (post_id, created_at DESC) WHERE deleted_at IS NULL;
