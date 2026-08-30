-- Migration: In-app announcement dialogs managed from the admin panel
--
-- The admin panel composes an announcement (markdown body with images,
-- links and emojis), picks the app screens it should appear on and how
-- many times each user may see it. The mobile app fetches active rows,
-- matches the current route against target_screens and shows a dialog,
-- counting views locally (SharedPreferences) against max_views.

CREATE TABLE IF NOT EXISTS public.app_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  target_screens TEXT[] NOT NULL DEFAULT '{}',
  max_views INT NOT NULL DEFAULT 1 CHECK (max_views >= 1),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.app_announcements IS
  'Admin-authored popup dialogs shown on selected app screens, capped at max_views per user.';

-- updated_at maintenance (search path pinned per database linter guidance)
CREATE OR REPLACE FUNCTION public.set_app_announcements_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER update_app_announcements_updated_at
  BEFORE UPDATE ON public.app_announcements
  FOR EACH ROW EXECUTE FUNCTION public.set_app_announcements_updated_at();

ALTER TABLE public.app_announcements ENABLE ROW LEVEL SECURITY;

-- The app reads active announcements (also pre-login); admins can read all rows.
CREATE POLICY "Anyone can read active announcements"
  ON public.app_announcements FOR SELECT
  USING (is_active = true OR public.is_admin(auth.uid()));

-- Only admins can create/update/delete announcements.
CREATE POLICY "Admins can manage announcements"
  ON public.app_announcements FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));
