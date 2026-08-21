-- public.notifications had two AFTER INSERT triggers both delivering pushes,
-- so every notification fired twice:
--   1. "send_push_notification" — dashboard-created webhook posting directly
--      to the Supabase edge function with a service_role JWT embedded in the
--      trigger definition.
--   2. "trigger_send_push_notification" — calls the config-driven
--      send_push_notification() plpgsql function, which posts via
--      _push_trigger_config to the api.instiy.com Cloudflare worker that
--      delivers to FCM directly (see 20260610120000).
-- Keep the config-driven path (#2) and drop the webhook (#1 duplicates).

DROP TRIGGER IF EXISTS send_push_notification ON public.notifications;
