-- Store the peer's display name with the recording so the Recordings
-- screen can render rows without extra user-table lookups.
ALTER TABLE public.call_recordings ADD COLUMN IF NOT EXISTS peer_name TEXT;
