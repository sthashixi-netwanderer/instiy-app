-- Replace the push notification trigger to use a config table instead of current_setting
-- (ALTER DATABASE/ROLE not available on Supabase hosted)

-- Config table for push notification trigger settings
CREATE TABLE IF NOT EXISTS public._push_trigger_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Lock down: no RLS, only SECURITY DEFINER functions access it
ALTER TABLE public._push_trigger_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "No direct access" ON public._push_trigger_config;
CREATE POLICY "No direct access"
  ON public._push_trigger_config FOR ALL
  USING (false);

-- Replace the trigger function to read from config table
CREATE OR REPLACE FUNCTION public.send_push_notification()
RETURNS TRIGGER AS $$
DECLARE
  v_url TEXT;
  v_anon_key TEXT;
  v_request_id BIGINT;
BEGIN
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_url';
  SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';

  IF v_url IS NULL OR v_anon_key IS NULL THEN
    RAISE LOG 'Push notification trigger: config not set';
    RETURN NEW;
  END IF;

  SELECT net.http_post(
    url := v_url || '/functions/v1/push-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key
    ),
    body := jsonb_build_object(
      'record', jsonb_build_object(
        'id', NEW.id,
        'user_id', NEW.user_id,
        'title', NEW.title,
        'body', NEW.body,
        'type', NEW.type,
        'data', NEW.data
      )
    )
  ) INTO v_request_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
