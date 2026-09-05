-- Migration: Allow service providers to showcase one video per service on the
-- Clips feed. Mirrors products.show_on_clips / products.clip_video_url.

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS show_on_clips BOOLEAN NOT NULL DEFAULT false;

-- When a service has multiple videos and show_on_clips = true, this stores the
-- URL of the specific video the provider chose for the Clips feed.
-- NULL means auto-use video_urls[0] (single-video services never need an
-- explicit selection).
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS clip_video_url TEXT;
