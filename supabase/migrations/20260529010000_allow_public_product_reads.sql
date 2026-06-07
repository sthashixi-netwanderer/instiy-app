-- Allow unauthenticated users to read available products

-- Drop the existing authenticated-only policy
DROP POLICY IF EXISTS "Anyone can view available products" ON public.products;

-- Recreate with public access (no TO clause = anyone including anon)
CREATE POLICY "Anyone can view available products"
  ON public.products FOR SELECT
  USING (true);
