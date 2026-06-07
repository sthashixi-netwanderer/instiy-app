-- Migration: Add thumbnail_url to products table
-- Allows sellers to designate one of their product images as the cover/thumbnail.
-- Falls back to the first image in image_urls if null.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- Backfill: set thumbnail_url to the first element of image_urls
-- for any existing products that have at least one image.
UPDATE public.products
  SET thumbnail_url = image_urls[1]
  WHERE thumbnail_url IS NULL
    AND array_length(image_urls, 1) > 0;
