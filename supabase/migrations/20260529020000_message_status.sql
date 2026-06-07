-- Add message status tracking (sent, delivered, seen)

-- 1. Add status column to messages
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'seen')),
  ADD COLUMN IF NOT EXISTS seen_at TIMESTAMP WITH TIME ZONE;

-- 2. Create index for efficient status queries
CREATE INDEX IF NOT EXISTS idx_messages_status ON public.messages(status);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_sender ON public.messages(conversation_id, sender_id);

-- 3. Function to mark messages as delivered when recipient opens the app
CREATE OR REPLACE FUNCTION mark_messages_delivered()
RETURNS TRIGGER AS $$
BEGIN
  -- Mark all undelivered messages in this conversation as delivered
  -- (where the recipient is the current user)
  UPDATE public.messages
  SET status = 'delivered'
  WHERE conversation_id = NEW.conversation_id
    AND sender_id != NEW.sender_id
    AND status = 'sent';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. Trigger to mark messages as delivered on new message insert
CREATE TRIGGER on_message_delivered
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION mark_messages_delivered();
