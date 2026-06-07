-- =============================================================
-- Chat Reply & Message Deletion System
-- =============================================================

-- 1. Add reply columns to messages table
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS reply_to_message_id UUID REFERENCES public.messages(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reply_to_content TEXT,
  ADD COLUMN IF NOT EXISTS reply_to_sender_name TEXT,
  ADD COLUMN IF NOT EXISTS reply_to_media_url TEXT,
  ADD COLUMN IF NOT EXISTS reply_to_media_type TEXT;

CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON public.messages(reply_to_message_id) WHERE reply_to_message_id IS NOT NULL;

-- 2. Message deletions table (soft-delete per user)
CREATE TABLE IF NOT EXISTS public.message_deletions (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_message_deletions_message ON public.message_deletions(message_id);
CREATE INDEX IF NOT EXISTS idx_message_deletions_user ON public.message_deletions(user_id);

-- 3. RLS for message_deletions
ALTER TABLE public.message_deletions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own deletions" ON public.message_deletions;
CREATE POLICY "Users can view own deletions"
  ON public.message_deletions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can create own deletions" ON public.message_deletions;
CREATE POLICY "Users can create own deletions"
  ON public.message_deletions FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own deletions" ON public.message_deletions;
CREATE POLICY "Users can delete own deletions"
  ON public.message_deletions FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- 4. DELETE policy on messages (sender can delete their own)
DROP POLICY IF EXISTS "Senders can delete own messages" ON public.messages;
CREATE POLICY "Senders can delete own messages"
  ON public.messages FOR DELETE
  TO authenticated
  USING (sender_id = auth.uid());

-- 5. Update SELECT policy to exclude deleted-for-me messages
DROP POLICY IF EXISTS "Participants can view messages" ON public.messages;
CREATE POLICY "Participants can view messages"
  ON public.messages FOR SELECT
  TO authenticated
  USING (
    conversation_id IN (
      SELECT id FROM public.conversations
      WHERE participant1_id = auth.uid() OR participant2_id = auth.uid()
    )
    AND id NOT IN (
      SELECT message_id FROM public.message_deletions
      WHERE user_id = auth.uid()
    )
  );

-- 6. Update handle_new_message to populate reply fields
CREATE OR REPLACE FUNCTION public.handle_new_message()
RETURNS TRIGGER AS $$
DECLARE
  _receiver_id UUID;
  _sender_name TEXT;
  _is_blocked BOOLEAN;
  _reply_sender_name TEXT;
  _reply_content TEXT;
  _reply_media_url TEXT;
  _reply_media_type TEXT;
BEGIN
  -- Find the other participant
  SELECT CASE
    WHEN c.participant1_id = NEW.sender_id THEN c.participant2_id
    ELSE c.participant1_id
  END INTO _receiver_id
  FROM public.conversations c
  WHERE c.id = NEW.conversation_id;

  -- Check if receiver has blocked the sender
  SELECT EXISTS(
    SELECT 1 FROM public.blocked_users
    WHERE blocker_id = _receiver_id AND blocked_id = NEW.sender_id
  ) INTO _is_blocked;

  -- If blocked, silently prevent the message
  IF _is_blocked THEN
    RETURN NULL;
  END IF;

  NEW.receiver_id := _receiver_id;

  -- Populate reply fields if replying to a message
  IF NEW.reply_to_message_id IS NOT NULL THEN
    SELECT
      COALESCE(u.full_name, 'Someone'),
      m.content,
      m.media_url,
      m.media_type
    INTO
      _reply_sender_name,
      _reply_content,
      _reply_media_url,
      _reply_media_type
    FROM public.messages m
    LEFT JOIN public.users u ON u.id = m.sender_id
    WHERE m.id = NEW.reply_to_message_id;

    NEW.reply_to_content := _reply_content;
    NEW.reply_to_sender_name := _reply_sender_name;
    NEW.reply_to_media_url := _reply_media_url;
    NEW.reply_to_media_type := _reply_media_type;
  END IF;

  -- Get sender name for notification
  SELECT COALESCE(u.full_name, 'Someone') INTO _sender_name
  FROM public.users u WHERE u.id = NEW.sender_id;

  -- Create notification
  INSERT INTO public.notifications (user_id, type, title, message, data)
  VALUES (
    _receiver_id,
    'new_message',
    _sender_name,
    CASE
      WHEN NEW.content IS NOT NULL AND NEW.content != '' THEN NEW.content
      WHEN NEW.media_type = 'video' THEN 'Sent a video'
      WHEN NEW.media_type = 'image' THEN 'Sent a photo'
      ELSE 'Sent a message'
    END,
    jsonb_build_object(
      'conversation_id', NEW.conversation_id,
      'sender_id', NEW.sender_id,
      'type', 'new_message'
    )
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Helper RPC: delete message for me
CREATE OR REPLACE FUNCTION public.delete_message_for_me(message_uuid UUID)
RETURNS VOID AS $$
BEGIN
  INSERT INTO public.message_deletions (message_id, user_id)
  VALUES (message_uuid, auth.uid())
  ON CONFLICT (message_id, user_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Enable realtime for message_deletions
ALTER PUBLICATION supabase_realtime ADD TABLE public.message_deletions;
