-- ─────────────────────────────────────────────────────────────────────────
-- Call recordings metadata. Media files live in R2 under recordings/<callId>/;
-- this table tracks who recorded, peer consent, and the ordered list of
-- uploaded segments (parts). Segmented capture means a call may end with
-- status 'recording' (partial) — the app finalizes it to 'complete' when the
-- trailing segments finish uploading.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.call_recordings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id UUID NOT NULL,
  recorded_by UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  peer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  call_type TEXT NOT NULL CHECK (call_type IN ('voice', 'video')),
  status TEXT NOT NULL DEFAULT 'recording' CHECK (status IN ('recording', 'complete', 'failed')),
  started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ended_at TIMESTAMPTZ,
  duration_seconds INT NOT NULL DEFAULT 0,
  parts JSONB NOT NULL DEFAULT '[]',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_call_recordings_recorded_by
  ON public.call_recordings(recorded_by, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_call_recordings_call_id
  ON public.call_recordings(call_id);

ALTER TABLE public.call_recordings ENABLE ROW LEVEL SECURITY;

-- Only the recorder sees and manages their recordings; the peer consented
-- live during the call but does not get a copy of the media.
CREATE POLICY call_recordings_recorder_all
  ON public.call_recordings
  FOR ALL
  TO authenticated
  USING (recorded_by = auth.uid())
  WITH CHECK (recorded_by = auth.uid());
