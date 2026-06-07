-- Video analytics: track views and shares for product clips

CREATE TABLE IF NOT EXISTS public.video_views (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  viewer_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  viewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_video_views_product_id ON public.video_views(product_id);
CREATE INDEX IF NOT EXISTS idx_video_views_viewer_id ON public.video_views(viewer_id);
CREATE INDEX IF NOT EXISTS idx_video_views_viewed_at ON public.video_views(viewed_at);

CREATE TABLE IF NOT EXISTS public.video_shares (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  sharer_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL CHECK (platform IN ('whatsapp', 'twitter', 'facebook', 'instagram', 'copy_link')),
  shared_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_video_shares_product_id ON public.video_shares(product_id);
CREATE INDEX IF NOT EXISTS idx_video_shares_sharer_id ON public.video_shares(sharer_id);
CREATE INDEX IF NOT EXISTS idx_video_shares_platform ON public.video_shares(platform);

-- RLS policies
ALTER TABLE public.video_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.video_shares ENABLE ROW LEVEL SECURITY;

-- Anyone can insert views (even anonymous)
CREATE POLICY "Anyone can insert video views"
  ON public.video_views FOR INSERT
  WITH CHECK (true);

-- Anyone can read video views (public data)
CREATE POLICY "Video views are public"
  ON public.video_views FOR SELECT
  USING (true);

-- Anyone can insert shares
CREATE POLICY "Anyone can insert video shares"
  ON public.video_shares FOR INSERT
  WITH CHECK (true);

-- Sellers can read shares for their own products
CREATE POLICY "Sellers can read own product shares"
  ON public.video_shares FOR SELECT
  USING (
    product_id IN (
      SELECT id FROM public.products WHERE seller_id = auth.uid()
    )
  );

-- RPC: Get video analytics for all of a seller's products
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
