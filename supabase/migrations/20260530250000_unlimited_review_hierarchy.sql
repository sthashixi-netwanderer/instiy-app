-- Migration to support unlimited nested review hierarchy (Twitter/X style replies)

-- 1. Drop the unique constraint that restricted a user to only one review/reply per product
ALTER TABLE public.product_reviews DROP CONSTRAINT IF EXISTS product_reviews_product_id_reviewer_id_key;

-- 2. Add parent_id to support infinite nesting
ALTER TABLE public.product_reviews ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES public.product_reviews(id) ON DELETE CASCADE;

-- 3. Make rating column nullable so replies/sub-replies don't require star ratings
ALTER TABLE public.product_reviews ALTER COLUMN rating DROP NOT NULL;

-- 4. Enforce that a user can only have ONE top-level review (rating/review) per product, while allowing unlimited replies
DROP INDEX IF EXISTS public.idx_product_reviews_unique_top_level;
CREATE UNIQUE INDEX idx_product_reviews_unique_top_level 
  ON public.product_reviews (product_id, reviewer_id) 
  WHERE (parent_id IS NULL);

-- 5. Add index on parent_id for high-performance hierarchy traversal
CREATE INDEX IF NOT EXISTS idx_product_reviews_parent_id ON public.product_reviews(parent_id);
