-- Enable Realtime on app_announcements so open apps pick up new/updated/
-- removed admin announcements immediately (the Riverpod provider listens
-- and refreshes its state on any change).
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_publication_tables
        WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'app_announcements'
    ) THEN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_announcements;
    END IF;
END $$;
