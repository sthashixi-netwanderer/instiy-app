-- ─────────────────────────────────────────────────────────────────────────
-- Product view tracking with dedup:
--   • Authenticated viewers  → one view per user per product
--   • Unauthenticated viewers → one view per IP per product
-- Direct table access is blocked (RLS, no policies); all access goes
-- through the SECURITY DEFINER RPCs below which only expose counts.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.product_views (
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  viewer_key TEXT NOT NULL,
  viewer_id UUID,
  viewer_ip TEXT,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (product_id, viewer_key)
);

CREATE INDEX IF NOT EXISTS idx_product_views_product_id
  ON public.product_views(product_id);

ALTER TABLE public.product_views ENABLE ROW LEVEL SECURITY;

-- No policies on purpose: anon/authenticated must not read or write raw rows
-- (viewer IPs stay private). The RPCs below are the only entry points.
REVOKE ALL ON TABLE public.product_views FROM anon, authenticated;

-- Records a view (deduped) and returns the product's total view count.
CREATE OR REPLACE FUNCTION public.record_product_view(
  p_product_id UUID,
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
  IF NOT EXISTS (SELECT 1 FROM public.products WHERE id = p_product_id) THEN
    RETURN 0;
  END IF;

  IF auth.uid() IS NOT NULL THEN
    v_key := 'u:' || auth.uid()::text;
    INSERT INTO public.product_views (product_id, viewer_key, viewer_id)
    VALUES (p_product_id, v_key, auth.uid())
    ON CONFLICT (product_id, viewer_key) DO NOTHING;
  ELSIF p_viewer_ip IS NOT NULL
        AND length(btrim(p_viewer_ip)) BETWEEN 7 AND 45 THEN
    v_key := 'ip:' || btrim(p_viewer_ip);
    INSERT INTO public.product_views (product_id, viewer_key, viewer_ip)
    VALUES (p_product_id, v_key, btrim(p_viewer_ip))
    ON CONFLICT (product_id, viewer_key) DO NOTHING;
  END IF;

  RETURN (SELECT COUNT(*) FROM public.product_views WHERE product_id = p_product_id);
END;
$$;

REVOKE ALL ON FUNCTION public.record_product_view(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_product_view(UUID, TEXT) TO anon, authenticated;

-- Bulk counts for lists (seller dashboard, product grids).
CREATE OR REPLACE FUNCTION public.get_product_view_counts(
  p_product_ids UUID[]
)
RETURNS TABLE (product_id UUID, view_count BIGINT)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
  SELECT v.product_id, COUNT(*)::BIGINT
  FROM public.product_views v
  WHERE v.product_id = ANY (p_product_ids)
  GROUP BY v.product_id;
$$;

REVOKE ALL ON FUNCTION public.get_product_view_counts(UUID[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_product_view_counts(UUID[]) TO anon, authenticated;
