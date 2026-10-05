ALTER TABLE notifications
  ADD COLUMN actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  ADD COLUMN title text,
  ADD COLUMN body text;

CREATE INDEX notifications_recipient_created_idx
  ON notifications (user_id, created_at DESC, id DESC);

CREATE INDEX notifications_recipient_unread_idx
  ON notifications (user_id, id)
  WHERE is_read = false;
