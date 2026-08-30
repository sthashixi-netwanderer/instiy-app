-- Migration: pin the app_announcements trigger function's search path
-- (database linter: function_search_path_mutable).
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
