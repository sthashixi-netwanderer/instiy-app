-- Migration: Add video_urls to products table
-- Allows sellers to upload and link videos for their products.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS video_urls TEXT[] DEFAULT '{}';
