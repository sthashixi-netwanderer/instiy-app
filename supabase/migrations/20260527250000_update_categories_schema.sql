-- Migration: Update Categories table schema to support CSV columns and category images
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS type TEXT CHECK (type IN ('product', 'service')) DEFAULT 'product';
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Backfill slugs and types for any existing categories
UPDATE public.categories 
SET slug = LOWER(REPLACE(name, ' & ', '-')), 
    type = 'product' 
WHERE slug IS NULL;
