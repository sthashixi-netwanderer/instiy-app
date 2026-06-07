-- Create function to handle new message triggers (determine receiver_id & insert notification)
CREATE OR REPLACE FUNCTION public.handle_new_message()
RETURNS TRIGGER AS $$
DECLARE
  v_receiver_id UUID;
  v_sender_name TEXT;
BEGIN
  -- 1. Find the other participant in the conversation to set as receiver_id
  SELECT CASE 
    WHEN participant1_id = NEW.sender_id THEN participant2_id 
    ELSE participant1_id 
  END INTO v_receiver_id
  FROM public.conversations 
  WHERE id = NEW.conversation_id;

  NEW.receiver_id := v_receiver_id;

  -- 2. Fetch the sender's full name for notification title
  SELECT full_name INTO v_sender_name 
  FROM public.users 
  WHERE id = NEW.sender_id;

  -- 3. Automatically insert a notification record for the receiver
  IF v_receiver_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_receiver_id,
      COALESCE(v_sender_name, 'New Message'),
      NEW.content,
      'message',
      jsonb_build_object('conversation_id', NEW.conversation_id, 'message_id', NEW.id)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the BEFORE INSERT trigger on public.messages
DROP TRIGGER IF EXISTS trigger_handle_new_message ON public.messages;
CREATE TRIGGER trigger_handle_new_message
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_message();

-- Enable Supabase Realtime for messages and notifications tables
-- (Check if already added, otherwise add them)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;
