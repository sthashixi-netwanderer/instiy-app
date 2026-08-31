-- Service-provider public email: shown on the service detail screen so
-- customers can contact the provider. Collected at opt-in (with a checkbox
-- to reuse the account email), editable from the Services screen, and
-- shown on the provider card of every listing the creator publishes.
--
-- Mirrors 20260830120000_service_provider_bio.sql.

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS service_provider_email TEXT;

-- User-writable column: per the column-freeze convention (see
-- 20260823110000_freeze_is_seller_column.sql) every new user-writable
-- column must be added to the column-level grant lists.
GRANT UPDATE (service_provider_email) ON TABLE public.users TO authenticated;
GRANT INSERT (service_provider_email) ON TABLE public.users TO authenticated;

-- Extend opt-in to also persist the public email. The new p_email parameter
-- defaults to NULL so the original one-arg call (used while only the bio
-- migration is deployed) keeps working.
DROP FUNCTION IF EXISTS public.become_service_provider(text);
CREATE FUNCTION public.become_service_provider(p_bio text, p_email text DEFAULT NULL)
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
      service_provider_email = NULLIF(btrim(p_email), ''),
      updated_at = now()
  WHERE id = auth.uid() AND NOT is_service_provider;
END;
$$;

REVOKE ALL ON FUNCTION public.become_service_provider(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.become_service_provider(text, text) TO authenticated;
