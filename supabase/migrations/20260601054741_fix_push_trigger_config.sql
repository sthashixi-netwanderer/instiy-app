-- Fix: drop RLS on config table and seed it with actual values

-- Drop the blocking RLS policy and disable RLS (internal table, not user-facing)
DROP POLICY IF EXISTS "No direct access" ON public._push_trigger_config;
ALTER TABLE public._push_trigger_config DISABLE ROW LEVEL SECURITY;

-- Seed the config values
INSERT INTO public._push_trigger_config (key, value)
VALUES
  ('supabase_url', 'https://wqasatrxqinkfaafgnli.supabase.co'),
  ('anon_key', 'sb_publishable_NiezrBMevDMxxJR79MD-AQ_XaRrGA9O')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
