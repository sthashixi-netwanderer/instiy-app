-- Allows a user to hide (soft-delete) a conversation from their own view only.
-- The other participant is completely unaffected.

CREATE TABLE IF NOT EXISTS conversation_hidden (
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, conversation_id)
);

ALTER TABLE conversation_hidden ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage their own hidden conversations"
  ON conversation_hidden
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
