-- Seller reply photo/video attachments (max 3 enforced client-side).
ALTER TABLE public.product_review_replies
  ADD COLUMN IF NOT EXISTS media_urls TEXT[] NOT NULL DEFAULT '{}';