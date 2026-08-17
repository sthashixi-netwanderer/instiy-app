-- Update push trigger config to use Cloudflare Workers API
-- This makes pg_net triggers call api.instiy.com instead of the Supabase edge functions

UPDATE public._push_trigger_config
SET value = 'https://api.instiy.com'
WHERE key = 'supabase_url';
