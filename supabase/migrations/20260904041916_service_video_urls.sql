-- Migration: Add video_urls to services table
-- Allows providers to attach short showcase videos to their services.

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS video_urls TEXT[] NOT NULL DEFAULT '{}';
