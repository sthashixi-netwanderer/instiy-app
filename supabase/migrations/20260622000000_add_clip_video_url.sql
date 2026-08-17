-- Add clip_video_url column to products table.
-- When a product has multiple videos and show_on_clips = true,
-- this stores the URL of the specific video the seller chose for the Clips feed.
-- NULL means auto-use videoUrls[0] (single-video products never need an explicit selection).
ALTER TABLE products ADD COLUMN IF NOT EXISTS clip_video_url TEXT;
