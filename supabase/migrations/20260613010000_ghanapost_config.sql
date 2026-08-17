-- Create Ghana Post GPS settings table
CREATE TABLE IF NOT EXISTS public.ghanapost_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.ghanapost_config ENABLE ROW LEVEL SECURITY;

-- Security check: helper is_admin_user already exists in public schema (created in ai_settings migration)
-- Admins can manage ghanapost_config
CREATE POLICY "Admins can manage ghanapost_config"
  ON public.ghanapost_config
  TO authenticated
  USING (public.is_admin_user(auth.uid()))
  WITH CHECK (public.is_admin_user(auth.uid()));

-- Authenticated users can view ghanapost_config (read-only for location lookup in Flutter app)
CREATE POLICY "Authenticated users can view ghanapost_config"
  ON public.ghanapost_config FOR SELECT
  TO authenticated
  USING (true);

-- Seed default values
INSERT INTO public.ghanapost_config (key, value)
VALUES 
  ('api_url', 'https://mijoride.ghanapostgps.com/user/get_address'),
  ('api_token', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJiYWIxNmZhMWQyODFkN2M1YWRmZTY0NDY1MmIyYWRkNSIsImlhdCI6MTc3ODUwMTA1MywiZXhwIjoxNzkwNTAxMDUzfQ.h07a2acw-_3mTz3nFPThCXPJX7FCe41Emq2lwq3Gjbc')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Add updated_at trigger
DROP TRIGGER IF EXISTS trigger_ghanapost_config_updated_at ON public.ghanapost_config;
CREATE TRIGGER trigger_ghanapost_config_updated_at
  BEFORE UPDATE ON public.ghanapost_config
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Add digital_address column to business_profiles
ALTER TABLE public.business_profiles
ADD COLUMN IF NOT EXISTS digital_address TEXT;

