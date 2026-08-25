-- Track where chat media came from so the UI can distinguish in-app
-- camera captures (photos / recorded videos) from gallery picks.
-- Values: 'camera' | 'gallery'. Null on legacy rows — only gallery
-- picking existed before, so null is treated as 'gallery'.
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS media_source TEXT;

COMMENT ON COLUMN public.messages.media_source IS
  'Origin of the attached media: camera (in-app capture) or gallery (picked). Null = legacy row, treated as gallery.';
