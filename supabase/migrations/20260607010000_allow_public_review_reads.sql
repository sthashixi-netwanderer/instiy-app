-- Allow unauthenticated users to read product reviews
-- (comment icon + count + comments sheet on the clip screen for guests)
-- Writes (insert/update/delete) remain restricted to authenticated users.

DROP POLICY IF EXISTS "Reviews are viewable by everyone" ON public.product_reviews;

CREATE POLICY "Reviews are viewable by everyone"
  ON public.product_reviews FOR SELECT
  USING (true);
