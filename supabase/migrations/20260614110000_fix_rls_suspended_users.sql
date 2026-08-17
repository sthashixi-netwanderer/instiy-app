-- ============================================================
-- Fix: Recreate restrictive policies without self-referencing users table
-- The is_user_suspended() function queries users, and the users
-- table had a restrictive policy calling that function, which
-- can cause PostgREST schema compilation to fail.
-- Fix: skip the users table (blocking all other tables is sufficient).
-- ============================================================

-- Drop ALL restrictive policies from previous migration
DO $$
DECLARE
  _tbl TEXT;
  _tables TEXT[] := ARRAY[
    'users', 'products', 'orders', 'reports', 'blocked_users',
    'conversations', 'messages', 'wallets', 'wallet_transactions',
    'notifications', 'product_reviews', 'product_review_replies',
    'favorites', 'user_push_tokens', 'business_profiles'
  ];
BEGIN
  FOREACH _tbl IN ARRAY _tables LOOP
    EXECUTE format(
      'DROP POLICY IF EXISTS "Deny suspended users" ON public.%I', _tbl
    );
  END LOOP;
END $$;

-- Recreate the helper function with defensive error handling
CREATE OR REPLACE FUNCTION public.is_user_suspended()
RETURNS BOOLEAN AS $$
  SELECT COALESCE(
    (SELECT suspended FROM public.users WHERE id = auth.uid()),
    FALSE
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Recreate restrictive policies on ALL tables EXCEPT users
-- (users table is skipped to avoid the self-reference issue)
DO $$
DECLARE
  _tbl TEXT;
  _tables TEXT[] := ARRAY[
    'products', 'orders', 'reports', 'blocked_users',
    'conversations', 'messages', 'wallets', 'wallet_transactions',
    'notifications', 'product_reviews', 'product_review_replies',
    'favorites', 'user_push_tokens', 'business_profiles'
  ];
BEGIN
  FOREACH _tbl IN ARRAY _tables LOOP
    EXECUTE format(
      'CREATE POLICY "Deny suspended users" ON public.%I AS RESTRICTIVE TO authenticated USING (NOT public.is_user_suspended())',
      _tbl
    );
  END LOOP;
END $$;
