-- Make users profiles publicly readable (for product detail seller cards when unauthenticated)
DROP POLICY IF EXISTS "Users can view all profiles" ON public.users;
CREATE POLICY "Users can view all profiles"
  ON public.users FOR SELECT
  USING (true);
