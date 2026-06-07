-- Migration: Allow unauthenticated users to read categories

-- Drop the existing authenticated-only policy
DROP POLICY IF EXISTS "Anyone can view categories" ON public.categories;

-- Recreate with public access (no TO clause = anyone including anon)
CREATE POLICY "Anyone can view categories"
  ON public.categories FOR SELECT
  USING (true);
