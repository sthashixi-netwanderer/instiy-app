-- Service-provider bio: a short description of the provider's services.
-- Collected (required) at opt-in, editable from the Services screen, and
-- shown under the provider card on the service detail screen.

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS service_provider_bio TEXT;

-- User-writable column: per the column-freeze convention (see
-- 20260823110000_freeze_is_seller_column.sql) every new user-writable
-- column must be added to the column-level grant lists.
GRANT UPDATE (service_provider_bio) ON TABLE public.users TO authenticated;
GRANT INSERT (service_provider_bio) ON TABLE public.users TO authenticated;

-- Opt-in now requires a bio and stores it in the same atomic, SECURITY
-- DEFINER call that flips is_service_provider (the flag itself stays
-- unwritable by clients).
DROP FUNCTION IF EXISTS public.become_service_provider();
CREATE FUNCTION public.become_service_provider(p_bio text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in';
  END IF;
  IF p_bio IS NULL OR btrim(p_bio) = '' THEN
    RAISE EXCEPTION 'A provider bio is required';
  END IF;

  UPDATE public.users
  SET is_service_provider = true,
      service_provider_bio = btrim(p_bio),
      updated_at = now()
  WHERE id = auth.uid() AND NOT is_service_provider;
END;
$$;

REVOKE ALL ON FUNCTION public.become_service_provider(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.become_service_provider(text) TO authenticated;
