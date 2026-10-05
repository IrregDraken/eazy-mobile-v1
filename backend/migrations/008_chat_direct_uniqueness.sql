DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM conversations c
    LEFT JOIN conversation_members cm
      ON cm.conversation_id = c.id AND cm.left_at IS NULL
    WHERE c.kind = 'direct'
    GROUP BY c.id
    HAVING count(cm.user_id) <> 2
  ) THEN
    RAISE EXCEPTION 'Cannot establish direct conversation pairs: an existing direct conversation does not have exactly two active members';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      SELECT array_agg(cm.user_id ORDER BY cm.user_id) AS member_pair
      FROM conversations c
      JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.left_at IS NULL
      WHERE c.kind = 'direct'
      GROUP BY c.id
      HAVING count(*) = 2
    ) pairs
    GROUP BY member_pair
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Cannot establish direct conversation pairs: duplicate direct conversations already exist';
  END IF;
END $$;

ALTER TABLE conversations
  ADD COLUMN direct_user_low_id uuid,
  ADD COLUMN direct_user_high_id uuid;

WITH direct_pairs AS (
  SELECT cm.conversation_id,
         (array_agg(cm.user_id ORDER BY cm.user_id))[1] AS low_id,
         (array_agg(cm.user_id ORDER BY cm.user_id))[2] AS high_id
  FROM conversation_members cm
  JOIN conversations c ON c.id = cm.conversation_id
  WHERE c.kind = 'direct' AND cm.left_at IS NULL
  GROUP BY cm.conversation_id
  HAVING count(*) = 2
)
UPDATE conversations c
SET direct_user_low_id = direct_pairs.low_id,
    direct_user_high_id = direct_pairs.high_id
FROM direct_pairs
WHERE c.id = direct_pairs.conversation_id;

ALTER TABLE conversations
  ADD CONSTRAINT conversations_direct_user_low_fkey
    FOREIGN KEY (direct_user_low_id) REFERENCES users(id) ON DELETE CASCADE,
  ADD CONSTRAINT conversations_direct_user_high_fkey
    FOREIGN KEY (direct_user_high_id) REFERENCES users(id) ON DELETE CASCADE,
  ADD CONSTRAINT conversations_direct_pair_check
    CHECK (
      (kind = 'direct'
        AND direct_user_low_id IS NOT NULL
        AND direct_user_high_id IS NOT NULL
        AND direct_user_low_id < direct_user_high_id)
      OR (kind <> 'direct'
        AND direct_user_low_id IS NULL
        AND direct_user_high_id IS NULL)
    );

CREATE UNIQUE INDEX conversations_direct_pair_key
  ON conversations (direct_user_low_id, direct_user_high_id)
  WHERE kind = 'direct';

CREATE INDEX conversation_members_user_active_idx
  ON conversation_members (user_id, conversation_id)
  WHERE left_at IS NULL;

CREATE INDEX messages_conversation_created_id_idx
  ON messages (conversation_id, created_at DESC, id DESC);

CREATE INDEX message_attachments_message_created_idx
  ON message_attachments (message_id, created_at, id);
