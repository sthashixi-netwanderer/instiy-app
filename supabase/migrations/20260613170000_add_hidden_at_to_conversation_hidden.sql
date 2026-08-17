-- Add hidden_at to conversation_hidden so we can implement WhatsApp-style
-- "delete chat" behaviour: messages sent BEFORE hidden_at stay hidden even
-- after the conversation resurfaces when the other user sends a new message.

ALTER TABLE conversation_hidden
  ADD COLUMN IF NOT EXISTS hidden_at timestamptz NOT NULL DEFAULT now();

-- Back-fill existing rows so created_at is used as the cutoff
UPDATE conversation_hidden SET hidden_at = created_at WHERE hidden_at = now();
