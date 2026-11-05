-- Give each Assist message a stable per-table sequence for deterministic chronology.
ALTER TABLE assist_messages
  ADD COLUMN IF NOT EXISTS sequence_id BIGINT GENERATED ALWAYS AS IDENTITY;

CREATE UNIQUE INDEX IF NOT EXISTS assist_messages_session_sequence_idx
  ON assist_messages (session_id, sequence_id);
