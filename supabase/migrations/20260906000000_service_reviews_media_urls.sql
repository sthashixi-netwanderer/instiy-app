-- Service review photo attachments (max 5 enforced client-side).
ALTER TABLE public.service_reviews
  ADD COLUMN IF NOT EXISTS media_urls TEXT[] NOT NULL DEFAULT '{}';
