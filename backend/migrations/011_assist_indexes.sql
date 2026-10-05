CREATE INDEX assist_sessions_user_updated_idx
  ON assist_sessions (user_id, updated_at DESC, id DESC);

CREATE INDEX assist_messages_session_created_idx
  ON assist_messages (session_id, created_at DESC, id DESC);
