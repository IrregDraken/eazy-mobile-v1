CREATE INDEX follows_followee_created_idx ON follows (followee_id, created_at DESC, follower_id);
CREATE INDEX follows_follower_created_idx ON follows (follower_id, created_at DESC, followee_id);
CREATE INDEX blocks_blocked_idx ON blocks (blocked_id, blocker_id);
CREATE INDEX profiles_display_name_search_idx ON profiles (lower(display_name));
CREATE INDEX profiles_username_search_idx ON profiles (lower(username));
CREATE INDEX reports_reporter_created_idx ON reports (reporter_id, created_at DESC);
