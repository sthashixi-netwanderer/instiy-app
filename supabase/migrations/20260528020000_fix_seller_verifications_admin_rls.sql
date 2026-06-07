-- Fix: seller_verifications admin RLS policies were using a direct subquery on
-- public.users instead of the is_admin() SECURITY DEFINER helper function.
-- The direct subquery can trigger RLS recursion or silently return no rows
-- because the users table's own RLS policies also check is_admin().
-- Replace them with public.is_admin(auth.uid()) which bypasses RLS safely.

-- Drop the broken admin policies
DROP POLICY IF EXISTS "Admins can view all verifications" ON public.seller_verifications;
DROP POLICY IF EXISTS "Admins can update all verifications" ON public.seller_verifications;

-- Recreate using the SECURITY DEFINER helper (same pattern as all other tables)
CREATE POLICY "Admins can view all verifications"
  ON public.seller_verifications
  FOR SELECT
  TO authenticated
  USING (public.is_admin(auth.uid()));

CREATE POLICY "Admins can update all verifications"
  ON public.seller_verifications
  FOR UPDATE
  TO authenticated
  USING (public.is_admin(auth.uid()));
