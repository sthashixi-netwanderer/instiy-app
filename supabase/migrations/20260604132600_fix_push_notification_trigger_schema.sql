-- Fix push notification trigger to use net.http_post instead of extensions.http_post

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
