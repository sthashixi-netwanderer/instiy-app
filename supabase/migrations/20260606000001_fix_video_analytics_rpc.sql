-- Fix ambiguous column reference in get_seller_video_analytics RPC
-- Drop the old buggy version and recreate with qualified column references

DROP FUNCTION IF EXISTS public.get_seller_video_analytics(UUID);

CREATE OR REPLACE FUNCTION public.get_seller_video_analytics(p_seller_id UUID)
RETURNS TABLE (
  product_id UUID,
  product_title TEXT,
  product_thumbnail TEXT,
  total_views BIGINT,
  unique_viewers BIGINT,
  total_likes BIGINT,
  total_shares BIGINT,
  shares_by JSONB
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id AS product_id,
    p.title AS product_title,
    COALESCE(p.thumbnail_url, (p.image_urls)[1]) AS product_thumbnail,
    COALESCE(v.view_count, 0) AS total_views,
    COALESCE(v.unique_count, 0) AS unique_viewers,
    COALESCE(f.like_count, 0) AS total_likes,
    COALESCE(s.share_count, 0) AS total_shares,
    COALESCE(s.shares_by, '{}'::jsonb) AS shares_by
  FROM public.products p
  LEFT JOIN (
    SELECT vv.product_id AS pid, COUNT(*) AS view_count, COUNT(DISTINCT vv.viewer_id) AS unique_count
    FROM public.video_views vv
    GROUP BY vv.product_id
  ) v ON v.pid = p.id
  LEFT JOIN (
    SELECT fav.product_id AS pid, COUNT(*) AS like_count
    FROM public.favorites fav
    GROUP BY fav.product_id
  ) f ON f.pid = p.id
  LEFT JOIN (
    SELECT
      sub.product_id AS pid,
      COUNT(*) AS share_count,
      jsonb_object_agg(sub.platform, sub.cnt) AS shares_by
    FROM (
      SELECT vs.product_id, vs.platform, COUNT(*) AS cnt
      FROM public.video_shares vs
      GROUP BY vs.product_id, vs.platform
    ) sub
    GROUP BY sub.product_id
  ) s ON s.pid = p.id
  WHERE p.seller_id = p_seller_id
    AND p.video_urls IS NOT NULL
    AND array_length(p.video_urls, 1) > 0
  ORDER BY COALESCE(v.view_count, 0) DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
