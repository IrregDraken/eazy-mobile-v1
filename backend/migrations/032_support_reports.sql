CREATE TABLE IF NOT EXISTS support_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN ('bug', 'account', 'payments', 'other')),
  subject VARCHAR(120) NOT NULL CHECK (length(trim(subject)) BETWEEN 5 AND 120),
  description TEXT NOT NULL CHECK (length(trim(description)) BETWEEN 20 AND 2000),
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'reviewing', 'resolved', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS support_reports_user_created_idx ON support_reports (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS support_reports_status_created_idx ON support_reports (status, created_at DESC);
