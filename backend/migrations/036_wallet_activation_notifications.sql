CREATE TABLE IF NOT EXISTS wallet_activation_notification_events (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  consented_at timestamptz NOT NULL,
  result text NOT NULL CHECK (result IN ('active', 'failed')),
  notification_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, consented_at, result)
);

ALTER TABLE wallet_activation_notification_events ENABLE ROW LEVEL SECURITY;
