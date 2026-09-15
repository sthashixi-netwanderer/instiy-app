-- Per-device notification sound for background push.
-- The app stores the user's chosen sound (a bundled sound id, or
-- 'device_default') on each push token so the push worker can address the
-- matching OS sound: an Android channel id / iOS sound file per token.

ALTER TABLE public.user_push_tokens
  ADD COLUMN IF NOT EXISTS sound TEXT NOT NULL DEFAULT 'device_default';
