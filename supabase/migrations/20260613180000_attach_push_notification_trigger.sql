-- The send_push_notification() function was defined but never attached to the
-- notifications table, so push notifications were NEVER sent when a notification
-- row was inserted. This binds the function as an AFTER INSERT trigger so users
-- receive push notifications even when the app is in the background or killed.

DROP TRIGGER IF EXISTS on_notification_created ON public.notifications;

CREATE TRIGGER on_notification_created
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.send_push_notification();
