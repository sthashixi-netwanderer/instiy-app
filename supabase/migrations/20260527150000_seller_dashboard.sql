-- Seller Dashboard: Product Reviews
CREATE TABLE IF NOT EXISTS public.product_reviews (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  reviewer_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  rating INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  helpful_count INTEGER DEFAULT 0,
  media_urls TEXT[] NOT NULL DEFAULT '{}',
  media_type TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(product_id, reviewer_id)
);

CREATE INDEX IF NOT EXISTS idx_product_reviews_product_id ON public.product_reviews(product_id);
CREATE INDEX IF NOT EXISTS idx_product_reviews_reviewer_id ON public.product_reviews(reviewer_id);

ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Reviews are viewable by everyone" ON public.product_reviews;
CREATE POLICY "Reviews are viewable by everyone"
  ON public.product_reviews FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Users can insert their own reviews" ON public.product_reviews;
CREATE POLICY "Users can insert their own reviews"
  ON public.product_reviews FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = reviewer_id);

DROP POLICY IF EXISTS "Users can update their own reviews" ON public.product_reviews;
CREATE POLICY "Users can update their own reviews"
  ON public.product_reviews FOR UPDATE
  TO authenticated
  USING (auth.uid() = reviewer_id);

DROP POLICY IF EXISTS "Users can delete their own reviews" ON public.product_reviews;
CREATE POLICY "Users can delete their own reviews"
  ON public.product_reviews FOR DELETE
  TO authenticated
  USING (auth.uid() = reviewer_id);

-- Seller Dashboard: Product Review Replies
CREATE TABLE IF NOT EXISTS public.product_review_replies (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  review_id UUID REFERENCES public.product_reviews(id) ON DELETE CASCADE NOT NULL,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  reply TEXT NOT NULL CHECK (char_length(btrim(reply)) > 0),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(review_id)
);

CREATE INDEX IF NOT EXISTS idx_product_review_replies_review_id ON public.product_review_replies(review_id);
CREATE INDEX IF NOT EXISTS idx_product_review_replies_seller_id ON public.product_review_replies(seller_id);

ALTER TABLE public.product_review_replies ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Review replies are viewable by everyone" ON public.product_review_replies;
CREATE POLICY "Review replies are viewable by everyone"
  ON public.product_review_replies FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Sellers can insert replies on their product reviews" ON public.product_review_replies;
CREATE POLICY "Sellers can insert replies on their product reviews"
  ON public.product_review_replies FOR INSERT
  TO authenticated
  WITH CHECK (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM public.product_reviews pr
      JOIN public.products p ON p.id = pr.product_id
      WHERE pr.id = review_id AND p.seller_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Sellers can update replies on their product reviews" ON public.product_review_replies;
CREATE POLICY "Sellers can update replies on their product reviews"
  ON public.product_review_replies FOR UPDATE
  TO authenticated
  USING (
    auth.uid() = seller_id
    AND EXISTS (
      SELECT 1 FROM public.product_reviews pr
      JOIN public.products p ON p.id = pr.product_id
      WHERE pr.id = review_id AND p.seller_id = auth.uid()
    )
  );

-- Seller Dashboard: Followers
CREATE TABLE IF NOT EXISTS public.seller_follows (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  follower_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(follower_id, seller_id),
  CHECK (follower_id != seller_id)
);

CREATE INDEX IF NOT EXISTS idx_seller_follows_follower_id ON public.seller_follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_seller_follows_seller_id ON public.seller_follows(seller_id);

ALTER TABLE public.seller_follows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "seller_follows_select_public" ON public.seller_follows;
CREATE POLICY "seller_follows_select_public"
  ON public.seller_follows FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "seller_follows_insert_own" ON public.seller_follows;
CREATE POLICY "seller_follows_insert_own"
  ON public.seller_follows FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = follower_id);

DROP POLICY IF EXISTS "seller_follows_delete_own" ON public.seller_follows;
CREATE POLICY "seller_follows_delete_own"
  ON public.seller_follows FOR DELETE
  TO authenticated
  USING (auth.uid() = follower_id);

-- Seller Dashboard: Follower Blocks
CREATE TABLE IF NOT EXISTS public.seller_follower_blocks (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  follower_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE (seller_id, follower_id),
  CHECK (seller_id <> follower_id)
);

CREATE INDEX IF NOT EXISTS idx_seller_follower_blocks_seller_id ON public.seller_follower_blocks(seller_id);
CREATE INDEX IF NOT EXISTS idx_seller_follower_blocks_follower_id ON public.seller_follower_blocks(follower_id);

ALTER TABLE public.seller_follower_blocks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "seller_follower_blocks_select_own" ON public.seller_follower_blocks;
CREATE POLICY "seller_follower_blocks_select_own"
  ON public.seller_follower_blocks FOR SELECT
  TO authenticated
  USING (auth.uid() = seller_id);

DROP POLICY IF EXISTS "seller_follower_blocks_insert_own" ON public.seller_follower_blocks;
CREATE POLICY "seller_follower_blocks_insert_own"
  ON public.seller_follower_blocks FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = seller_id);

DROP POLICY IF EXISTS "seller_follower_blocks_delete_own" ON public.seller_follower_blocks;
CREATE POLICY "seller_follower_blocks_delete_own"
  ON public.seller_follower_blocks FOR DELETE
  TO authenticated
  USING (auth.uid() = seller_id);

-- Add updated_at triggers for new tables
DROP TRIGGER IF EXISTS trigger_product_reviews_updated_at ON public.product_reviews;
CREATE TRIGGER trigger_product_reviews_updated_at
  BEFORE UPDATE ON public.product_reviews
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_product_review_replies_updated_at ON public.product_review_replies;
CREATE TRIGGER trigger_product_review_replies_updated_at
  BEFORE UPDATE ON public.product_review_replies
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Enable Realtime for product_reviews
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'product_reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.product_reviews;
  END IF;
END $$;
