-- Fix push notification delivery from the notifications INSERT trigger.
--
-- Root cause: send_push_notification() posts to <supabase_url>/functions/v1/
-- push-notifications, but supabase_url points at the Cloudflare worker
-- (api.instiy.com). That route is handled by the worker's own
-- push-notifications handler, whose FCM credentials path is broken — every
-- push for a user with registered FCM tokens returned
-- {"error":"Failed to process push notifications"} (HTTP 500). Callees with
-- a backgrounded app therefore never saw incoming-call pushes at all.
--
-- Same class of bug as 20260823140000_fix_notification_delivery.sql (which
-- repointed send-sms / send-email but missed the push trigger): the database
-- must call the Supabase Edge Functions directly, whose FCM setup is verified
-- working.
--
-- This migration repoints the trigger at supabase_functions_url.

CREATE OR REPLACE FUNCTION public.send_push_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_url TEXT;
  v_anon_key TEXT;
  v_request_id BIGINT;
BEGIN
  -- Direct Edge Functions URL. supabase_url points at the Cloudflare worker,
  -- whose push-notifications handler cannot deliver FCM pushes (500s).
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_functions_url';
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
$function$;
