-- Migration: Disable service provider restrictions & auto-suspend services
-- 
-- 1. When users.is_service_provider is turned off (false) or user is suspended:
--    - Automatically set all their services' status to 'inactive' so they are hidden from Discover.
-- 2. Tighten services RLS policies:
--    - Creating services strictly requires public.is_service_provider(auth.uid()) AND NOT suspended.
--    - Updating services strictly requires public.is_service_provider(auth.uid()) AND NOT suspended.
--    - Managing service_packages strictly requires provider to have is_service_provider = true.
-- 3. Provide admin_set_service_provider(p_user_id, p_is_service_provider) RPC:
--    - Enables admins to toggle is_service_provider for any user.

-- 1. Admin RPC for toggling is_service_provider
CREATE OR REPLACE FUNCTION public.admin_set_service_provider(
  p_user_id uuid,
  p_is_service_provider boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only administrators can change service provider status';
  END IF;

  UPDATE public.users
  SET is_service_provider = p_is_service_provider,
      updated_at = now()
  WHERE id = p_user_id;

  -- If disabled, deactivate all their services immediately
  IF NOT p_is_service_provider THEN
    UPDATE public.services
    SET status = 'inactive',
        updated_at = now()
    WHERE provider_id = p_user_id
      AND status != 'inactive';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_service_provider(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_service_provider(uuid, boolean) TO authenticated;

-- 2. Trigger on users to suspend/hide services whenever is_service_provider is disabled or user suspended
CREATE OR REPLACE FUNCTION public.handle_user_service_provider_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- When is_service_provider is flipped to false or user is suspended, deactivate all active/paused services
  IF (OLD.is_service_provider AND NOT NEW.is_service_provider)
     OR (NOT NEW.is_service_provider AND OLD.is_service_provider IS DISTINCT FROM NEW.is_service_provider)
     OR (NOT OLD.suspended AND NEW.suspended) THEN
    UPDATE public.services
    SET status = 'inactive',
        updated_at = now()
    WHERE provider_id = NEW.id
      AND status != 'inactive';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_handle_user_service_provider_status_change ON public.users;
CREATE TRIGGER trigger_handle_user_service_provider_status_change
  AFTER UPDATE OF is_service_provider, suspended ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_user_service_provider_status_change();

-- 3. Tighten RLS policies on public.services
DROP POLICY IF EXISTS "Providers can create services" ON public.services;
CREATE POLICY "Providers can create services"
  ON public.services FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = provider_id
    AND public.is_service_provider(auth.uid())
    AND NOT public.is_user_suspended()
  );

DROP POLICY IF EXISTS "Providers can update own services" ON public.services;
CREATE POLICY "Providers can update own services"
  ON public.services FOR UPDATE TO authenticated
  USING (
    auth.uid() = provider_id
    AND public.is_service_provider(auth.uid())
    AND NOT public.is_user_suspended()
  )
  WITH CHECK (
    auth.uid() = provider_id
    AND public.is_service_provider(auth.uid())
    AND NOT public.is_user_suspended()
  );

-- 4. Tighten RLS on public.service_packages
DROP POLICY IF EXISTS "Providers can manage own service packages" ON public.service_packages;
CREATE POLICY "Providers can manage own service packages"
  ON public.service_packages FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.services s
      WHERE s.id = service_id
        AND s.provider_id = auth.uid()
    )
    AND public.is_service_provider(auth.uid())
    AND NOT public.is_user_suspended()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.services s
      WHERE s.id = service_id
        AND s.provider_id = auth.uid()
    )
    AND public.is_service_provider(auth.uid())
    AND NOT public.is_user_suspended()
  );
