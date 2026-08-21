-- RPC for clients to create notifications.
--
-- public.notifications has RLS enabled with only SELECT/UPDATE policies and no
-- INSERT policy (server-side RPCs like place_order_with_items insert directly),
-- so client-side INSERTs are rejected with "new row violates row-level
-- security policy". The purchase permission flow inserted from the client and
-- every notification silently failed. Clients must go through this SECURITY
-- DEFINER function instead. The on_notification_created trigger still fires
-- inside it, so push notifications keep working.

CREATE OR REPLACE FUNCTION public.create_notification(
  p_user_id UUID,
  p_title TEXT,
  p_body TEXT,
  p_type TEXT DEFAULT 'system',
  p_data JSONB DEFAULT '{}'::jsonb
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (p_user_id, p_title, p_body, p_type, p_data);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_notification(UUID, TEXT, TEXT, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_notification(UUID, TEXT, TEXT, TEXT, JSONB) TO authenticated;
