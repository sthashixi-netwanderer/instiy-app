-- Create user_push_tokens table to track FCM tokens for background push notifications

CREATE TABLE IF NOT EXISTS public.user_push_tokens (
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  token TEXT PRIMARY KEY,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_id ON public.user_push_tokens(user_id);

-- Enable Row Level Security
ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;

-- Add RLS policy: Users can insert, update, or read their own push tokens
DROP POLICY IF EXISTS "Users can manage their own tokens" ON public.user_push_tokens;
CREATE POLICY "Users can manage their own tokens"
  ON public.user_push_tokens FOR ALL
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Enable Realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.user_push_tokens;
