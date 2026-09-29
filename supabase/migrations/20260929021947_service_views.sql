-- ─────────────────────────────────────────────────────────────────────────
-- Service view tracking with dedup (mirrors product_views):
--   • Authenticated viewers  → one view per user per service
--   • Unauthenticated viewers → one view per IP per service
-- Direct table access is blocked (RLS, no policies); all access goes
-- through the SECURITY DEFINER RPCs below which only expose counts.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.service_views (
  service_id UUID NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  viewer_key TEXT NOT NULL,
  viewer_id UUID,
  viewer_ip TEXT,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (service_id, viewer_key)
);

CREATE INDEX IF NOT EXISTS idx_service_views_service_id
  ON public.service_views(service_id);

ALTER TABLE public.service_views ENABLE ROW LEVEL SECURITY;

-- No policies on purpose: anon/authenticated must not read or write raw rows
-- (viewer IPs stay private). The RPCs below are the only entry points.
REVOKE ALL ON TABLE public.service_views FROM anon, authenticated;

-- Records a view (deduped) and returns the service's total view count.
CREATE OR REPLACE FUNCTION public.record_service_view(
  p_service_id UUID,
  p_viewer_ip TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_key TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.services WHERE id = p_service_id) THEN
    RETURN 0;
  END IF;

  IF auth.uid() IS NOT NULL THEN
    v_key := 'u:' || auth.uid()::text;
    INSERT INTO public.service_views (service_id, viewer_key, viewer_id)
    VALUES (p_service_id, v_key, auth.uid())
    ON CONFLICT (service_id, viewer_key) DO NOTHING;
  ELSIF p_viewer_ip IS NOT NULL
        AND length(btrim(p_viewer_ip)) BETWEEN 7 AND 45 THEN
    v_key := 'ip:' || btrim(p_viewer_ip);
    INSERT INTO public.service_views (service_id, viewer_key, viewer_ip)
    VALUES (p_service_id, v_key, btrim(p_viewer_ip))
    ON CONFLICT (service_id, viewer_key) DO NOTHING;
  END IF;

  RETURN (SELECT COUNT(*) FROM public.service_views WHERE service_id = p_service_id);
END;
$$;

REVOKE ALL ON FUNCTION public.record_service_view(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_service_view(UUID, TEXT) TO anon, authenticated;

-- Bulk counts for lists (provider dashboard Services panel).
CREATE OR REPLACE FUNCTION public.get_service_view_counts(
  p_service_ids UUID[]
)
RETURNS TABLE (service_id UUID, view_count BIGINT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT v.service_id, COUNT(*)::BIGINT
  FROM public.service_views v
  WHERE v.service_id = ANY (p_service_ids)
  GROUP BY v.service_id;
$$;

REVOKE ALL ON FUNCTION public.get_service_view_counts(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_service_view_counts(UUID[]) TO anon, authenticated;
