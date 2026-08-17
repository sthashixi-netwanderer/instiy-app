-- ============================================================
-- Server-side enforcement: deny ALL operations for suspended users
-- Uses RESTRICTIVE policies (AND logic) on top of existing
-- permissive policies. Suspended users cannot access any data
-- except user_complaints (so they can submit complaints).
-- ============================================================

-- Helper function: returns true if the current user is suspended
CREATE OR REPLACE FUNCTION public.is_user_suspended()
RETURNS BOOLEAN AS $$
  SELECT COALESCE(
    (SELECT suspended FROM public.users WHERE id = auth.uid()),
    FALSE
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Helper to safely create restrictive policies (idempotent)
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
    EXECUTE format(
      'CREATE POLICY "Deny suspended users" ON public.%I AS RESTRICTIVE TO authenticated USING (NOT public.is_user_suspended())',
      _tbl
    );
  END LOOP;
END $$;
