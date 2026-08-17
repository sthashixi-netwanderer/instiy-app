-- Add last_seen column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_seen TIMESTAMP WITH TIME ZONE;

-- Index for efficient last_seen lookups
CREATE INDEX IF NOT EXISTS idx_users_last_seen ON public.users (id, last_seen);

-- Update last_seen on every auth request via a function
CREATE OR REPLACE FUNCTION public.update_last_seen()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.users SET last_seen = NOW() WHERE id = auth.uid();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to update last_seen when user makes a request (via Supabase RPC or table access)
-- We'll use a simpler approach: update last_seen via the app on each screen load
