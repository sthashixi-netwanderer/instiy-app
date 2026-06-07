-- Per-user conversation archive status
-- Each user can independently archive/unarchive a conversation
CREATE TABLE IF NOT EXISTS public.conversation_archives (
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, conversation_id)
);

CREATE INDEX IF NOT EXISTS idx_conv_archives_user ON public.conversation_archives(user_id);
CREATE INDEX IF NOT EXISTS idx_conv_archives_conv ON public.conversation_archives(conversation_id);

-- RLS: users can manage their own archives
ALTER TABLE public.conversation_archives ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own archives"
  ON public.conversation_archives FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own archives"
  ON public.conversation_archives FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete own archives"
  ON public.conversation_archives FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
