-- Business Profiles table
CREATE TABLE IF NOT EXISTS public.business_profiles (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  banner_url TEXT,
  business_name TEXT,
  description TEXT,
  phone_numbers JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_business_profiles_seller_id ON public.business_profiles(seller_id);

ALTER TABLE public.business_profiles ENABLE ROW LEVEL SECURITY;

-- Anyone can view business profiles
DROP POLICY IF EXISTS "Business profiles are viewable by everyone" ON public.business_profiles;
CREATE POLICY "Business profiles are viewable by everyone"
  ON public.business_profiles FOR SELECT
  USING (true);

-- Sellers can insert their own profile
DROP POLICY IF EXISTS "Sellers can insert own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can insert own business profile"
  ON public.business_profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = seller_id);

-- Sellers can update their own profile
DROP POLICY IF EXISTS "Sellers can update own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can update own business profile"
  ON public.business_profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = seller_id);

-- updated_at trigger
DROP TRIGGER IF EXISTS trigger_business_profiles_updated_at ON public.business_profiles;
CREATE TRIGGER trigger_business_profiles_updated_at
  BEFORE UPDATE ON public.business_profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Enable Realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'business_profiles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.business_profiles;
  END IF;
END $$;

-- RPC: Get seller store stats
CREATE OR REPLACE FUNCTION get_seller_store_stats(p_seller_id UUID)
RETURNS TABLE (
  follower_count BIGINT,
  review_count BIGINT,
  average_rating NUMERIC,
  total_products BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    (SELECT COUNT(*) FROM public.seller_follows WHERE seller_id = p_seller_id),
    (SELECT COUNT(*) FROM public.product_reviews pr
     JOIN public.products p ON p.id = pr.product_id
     WHERE p.seller_id = p_seller_id),
    (SELECT COALESCE(AVG(pr.rating), 0) FROM public.product_reviews pr
     JOIN public.products p ON p.id = pr.product_id
     WHERE p.seller_id = p_seller_id),
    (SELECT COUNT(*) FROM public.products WHERE seller_id = p_seller_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Get seller store reviews (paginated, across all products)
CREATE OR REPLACE FUNCTION get_seller_store_reviews(
  p_seller_id UUID,
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  product_id UUID,
  reviewer_id UUID,
  rating INT,
  comment TEXT,
  media_urls TEXT[],
  helpful_count INT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  reviewer_name TEXT,
  reviewer_avatar TEXT,
  product_title TEXT,
  product_thumbnail TEXT,
  reply TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pr.id,
    pr.product_id,
    pr.reviewer_id,
    pr.rating,
    pr.comment,
    pr.media_urls,
    pr.helpful_count,
    pr.created_at,
    pr.updated_at,
    u.full_name AS reviewer_name,
    u.avatar_url AS reviewer_avatar,
    p.title AS product_title,
    CASE
      WHEN p.image_urls IS NOT NULL AND array_length(p.image_urls, 1) > 0
      THEN p.image_urls[1]
      ELSE p.thumbnail_url
    END AS product_thumbnail,
    (SELECT prr.reply FROM public.product_review_replies prr WHERE prr.review_id = pr.id LIMIT 1) AS reply
  FROM public.product_reviews pr
  JOIN public.products p ON p.id = pr.product_id
  JOIN public.users u ON u.id = pr.reviewer_id
  WHERE p.seller_id = p_seller_id AND pr.parent_id IS NULL
  ORDER BY pr.created_at DESC
  OFFSET p_offset
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC: Check if current user is following a seller
CREATE OR REPLACE FUNCTION is_following_seller(p_seller_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.seller_follows
    WHERE seller_id = p_seller_id AND follower_id = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
