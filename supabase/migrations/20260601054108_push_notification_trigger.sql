-- Restore the trigger to use current_setting (run AFTER configuring app.settings via dashboard)
-- This migration replaces the trigger function with one that uses app.settings config

CREATE OR REPLACE FUNCTION public.send_push_notification()
RETURNS TRIGGER AS $$
DECLARE
  v_service_role_key TEXT;
  v_supabase_url TEXT;
  v_request_id BIGINT;
BEGIN
  BEGIN
    v_service_role_key := current_setting('app.settings.service_role_key', true);
    v_supabase_url := current_setting('app.settings.supabase_url', true);
  EXCEPTION WHEN OTHERS THEN
    RAISE LOG 'Push notification trigger: app.settings not configured, skipping';
    RETURN NEW;
  END;

  IF v_service_role_key IS NULL OR v_service_role_key = '' OR
     v_supabase_url IS NULL OR v_supabase_url = '' THEN
    RAISE LOG 'Push notification trigger: service_role_key or supabase_url not set';
    RETURN NEW;
  END IF;

  SELECT net.http_post(
    url := v_supabase_url || '/functions/v1/push-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_service_role_key
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
