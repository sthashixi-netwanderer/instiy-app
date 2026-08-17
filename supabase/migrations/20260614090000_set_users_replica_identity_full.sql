-- Required for Realtime UPDATE payloads to include full row data
-- Without this, newRecord may not contain all columns
ALTER TABLE public.users REPLICA IDENTITY FULL;
