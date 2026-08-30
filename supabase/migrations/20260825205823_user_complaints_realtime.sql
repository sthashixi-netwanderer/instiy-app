-- Expose user_complaints to Realtime so the admin Reports page can live-refresh
-- the suspended-complaints queue. RLS stays enabled: admins receive all rows,
-- regular users only rows they can SELECT (their own).
alter publication supabase_realtime add table public.user_complaints;
