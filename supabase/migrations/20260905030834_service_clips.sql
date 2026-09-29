ALTER TABLE public.services ADD COLUMN IF NOT EXISTS show_on_clips BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.services ADD COLUMN IF NOT EXISTS clip_video_url TEXT;
