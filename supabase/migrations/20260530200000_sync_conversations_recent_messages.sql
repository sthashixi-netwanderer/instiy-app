-- Re-define handle_new_message trigger function to update public.conversations
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

  -- Create notification (correctly using 'body' column instead of 'message')
  INSERT INTO public.notifications (user_id, type, title, body, data)
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

  -- Update conversation last_message and last_message_at
  UPDATE public.conversations
  SET last_message = CASE
        WHEN NEW.media_type = 'video' THEN 
          CASE WHEN NEW.content IS NOT NULL AND NEW.content != '' THEN '📹 Video: ' || NEW.content ELSE '📹 Video' END
        WHEN NEW.media_type = 'image' THEN 
          CASE WHEN NEW.content IS NOT NULL AND NEW.content != '' THEN '📷 Photo: ' || NEW.content ELSE '📷 Photo' END
        WHEN NEW.product_reference IS NOT NULL THEN
          '📷 Shared: ' || COALESCE(NEW.product_reference->>'title', 'Product')
        WHEN NEW.content IS NOT NULL AND NEW.content != '' THEN
          CASE WHEN NEW.reply_to_message_id IS NOT NULL THEN '↩️ ' || NEW.content ELSE NEW.content END
        ELSE 'Sent a message'
      END,
      last_message_at = COALESCE(NEW.created_at, NOW())
  WHERE id = NEW.conversation_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Backfill existing conversations with details from their latest message
UPDATE public.conversations c
SET 
  last_message = CASE
    WHEN m.media_type = 'video' THEN 
      CASE WHEN m.content IS NOT NULL AND m.content != '' THEN '📹 Video: ' || m.content ELSE '📹 Video' END
    WHEN m.media_type = 'image' THEN 
      CASE WHEN m.content IS NOT NULL AND m.content != '' THEN '📷 Photo: ' || m.content ELSE '📷 Photo' END
    WHEN m.product_reference IS NOT NULL THEN
      '📷 Shared: ' || COALESCE(m.product_reference->>'title', 'Product')
    WHEN m.content IS NOT NULL AND m.content != '' THEN
      CASE WHEN m.reply_to_message_id IS NOT NULL THEN '↩️ ' || m.content ELSE m.content END
    ELSE 'Sent a message'
  END,
  last_message_at = m.created_at
FROM (
  SELECT conversation_id, content, media_type, product_reference, reply_to_message_id, created_at,
         ROW_NUMBER() OVER (PARTITION BY conversation_id ORDER BY created_at DESC) as rn
  FROM public.messages
) m
WHERE c.id = m.conversation_id AND m.rn = 1;
