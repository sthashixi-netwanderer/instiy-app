-- Become a Seller: explicit, irreversible seller opt-in.
-- users.is_seller is the single source of truth for seller status.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_seller boolean NOT NULL DEFAULT false;

-- One-time backfill: existing sellers (products or business profile) keep access.
UPDATE public.users
SET is_seller = true, updated_at = now()
WHERE id IN (
  SELECT seller_id FROM public.products
  UNION
  SELECT seller_id FROM public.business_profiles
);

-- Helper used by RLS policies.
CREATE OR REPLACE FUNCTION public.is_seller(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT u.is_seller FROM public.users u WHERE u.id = p_user_id),
    false
  );
$$;

-- One-way RPC: creates/updates the business profile and flips the flag atomically.
CREATE OR REPLACE FUNCTION public.become_seller(
  p_business_name text,
  p_description text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in';
  END IF;
  IF p_business_name IS NULL OR length(btrim(p_business_name)) < 2 THEN
    RAISE EXCEPTION 'Business name must be at least 2 characters';
  END IF;

  INSERT INTO public.business_profiles (seller_id, business_name, description)
  VALUES (auth.uid(), btrim(p_business_name), NULLIF(btrim(COALESCE(p_description, '')), ''))
  ON CONFLICT (seller_id) DO UPDATE
    SET business_name = EXCLUDED.business_name,
        description   = EXCLUDED.description,
        updated_at    = now();

  UPDATE public.users
  SET is_seller = true, updated_at = now()
  WHERE id = auth.uid() AND NOT is_seller;
END;
$$;

REVOKE ALL ON FUNCTION public.become_seller(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.become_seller(text, text) TO authenticated;

-- Freeze is_seller against self-service changes: only the SECURITY DEFINER
-- become_seller() RPC (and the service role / table owner) may write the
-- column. RLS policy expressions cannot compare OLD vs NEW values, so this
-- is enforced with column-level privileges instead.
REVOKE UPDATE (is_seller) ON TABLE public.users FROM PUBLIC, anon, authenticated;
REVOKE INSERT (is_seller) ON TABLE public.users FROM PUBLIC, anon, authenticated;

-- Ratchet: is_seller can never go true -> false, except via the service role
-- or an admin (same escape hatch as the is_verified revoke flow).
CREATE OR REPLACE FUNCTION public.enforce_seller_ratchet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.is_seller AND NOT NEW.is_seller
     AND auth.uid() IS NOT NULL
     AND NOT public.is_admin(auth.uid()) THEN
    NEW.is_seller := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_users_seller_ratchet ON public.users;
CREATE TRIGGER trigger_users_seller_ratchet
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_seller_ratchet();

-- Selling is now seller-only at the database level (INSERT paths only).
DROP POLICY IF EXISTS "Users can create own products" ON public.products;
CREATE POLICY "Users can create own products"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));

DROP POLICY IF EXISTS "Providers can create services" ON public.services;
CREATE POLICY "Providers can create services"
  ON public.services FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = provider_id AND public.is_seller(auth.uid()));

DROP POLICY IF EXISTS "Sellers can insert own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can insert own business profile"
  ON public.business_profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));

DROP POLICY IF EXISTS "Sellers can update own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can update own business profile"
  ON public.business_profiles FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id AND public.is_seller(auth.uid()))
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));
