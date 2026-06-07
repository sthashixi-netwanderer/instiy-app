-- Ensure media_type column exists in product_reviews (schema cache safety)
ALTER TABLE public.product_reviews
ADD COLUMN IF NOT EXISTS media_type TEXT;

-- Notify PostgREST to refresh its schema cache
NOTIFY pgrst, 'reload schema';
