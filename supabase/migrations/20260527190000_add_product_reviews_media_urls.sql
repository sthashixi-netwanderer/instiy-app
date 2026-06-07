-- Add missing media_urls column to product_reviews (schema cache safety)
ALTER TABLE public.product_reviews
ADD COLUMN IF NOT EXISTS media_urls TEXT[] NOT NULL DEFAULT '{}';

-- Notify PostgREST to refresh its schema cache
NOTIFY pgrst, 'reload schema';
