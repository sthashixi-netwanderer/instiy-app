-- Realtime for service categories.
--
-- The Services screen's realtime channel listens for category changes to
-- refresh its filter chips. Postgres changes are only delivered for tables
-- in the supabase_realtime publication, and a table missing from it gets
-- the whole channel rejected — so this must exist before the client
-- subscribes to `categories`.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'categories'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.categories;
  END IF;
END $$;
