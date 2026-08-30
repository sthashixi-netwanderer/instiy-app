-- Services marketplace: Fiverr-style listings with pricing packages,
-- a dedicated service-provider opt-in, and creator management access
-- that lives only in the app's Services screen.
--
-- Part 1 mirrors the become_seller opt-in (users.is_service_provider is a
-- one-way ratchet only flippable via the SECURITY DEFINER RPC).
-- Part 2 extends public.services with category FK, search tags and delivery
-- time, and adds the service_packages child table (basic/standard/premium).
-- Part 3 rebuilds services RLS: public browse reads, provider-gated writes,
-- owner delete. service_packages is publicly readable, owner-managed.
-- Part 4 seeds service-type categories.

-- ============================================================
-- 1. Service-provider opt-in (mirrors users.is_seller)
-- ============================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_service_provider boolean NOT NULL DEFAULT false;

-- Existing service rows keep their creators listed.
UPDATE public.users
SET is_service_provider = true, updated_at = now()
WHERE id IN (SELECT DISTINCT provider_id FROM public.services);

-- Helper used by RLS policies.
CREATE OR REPLACE FUNCTION public.is_service_provider(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT u.is_service_provider FROM public.users u WHERE u.id = p_user_id),
    false
  );
$$;

-- One-way RPC: flips the flag. Sellers already qualify; everyone else opts
-- in explicitly from the Services screen.
CREATE OR REPLACE FUNCTION public.become_service_provider()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in';
  END IF;

  UPDATE public.users
  SET is_service_provider = true, updated_at = now()
  WHERE id = auth.uid() AND NOT is_service_provider;
END;
$$;

REVOKE ALL ON FUNCTION public.become_service_provider() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.become_service_provider() TO authenticated;

-- Freeze is_service_provider against self-service changes: only the
-- SECURITY DEFINER RPC (and the service role / table owner / admins) may
-- write the column.
REVOKE UPDATE (is_service_provider) ON TABLE public.users FROM PUBLIC, anon, authenticated;
REVOKE INSERT (is_service_provider) ON TABLE public.users FROM PUBLIC, anon, authenticated;

-- Ratchet: can never go true -> false, except via the service role or admin.
CREATE OR REPLACE FUNCTION public.enforce_service_provider_ratchet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.is_service_provider AND NOT NEW.is_service_provider
     AND auth.uid() IS NOT NULL
     AND NOT public.is_admin(auth.uid()) THEN
    NEW.is_service_provider := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_users_service_provider_ratchet ON public.users;
CREATE TRIGGER trigger_users_service_provider_ratchet
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_service_provider_ratchet();

-- ============================================================
-- 2. services extensions + service_packages
-- ============================================================

ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL;
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS search_tags TEXT[] NOT NULL DEFAULT '{}';
ALTER TABLE public.services
  ADD COLUMN IF NOT EXISTS delivery_days INT CHECK (delivery_days IS NULL OR delivery_days >= 1);

-- Link legacy free-text category values to the categories table.
UPDATE public.services s
SET category_id = (SELECT c.id FROM public.categories c WHERE c.name = s.category LIMIT 1)
WHERE s.category_id IS NULL AND s.category IS NOT NULL;

-- Pricing tiers per service (Fiverr-style Basic / Standard / Premium).
CREATE TABLE IF NOT EXISTS public.service_packages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id UUID NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  tier TEXT NOT NULL CHECK (tier IN ('basic', 'standard', 'premium')),
  name TEXT NOT NULL DEFAULT '',
  description TEXT NOT NULL DEFAULT '',
  price DECIMAL(10, 2) NOT NULL CHECK (price >= 0),
  delivery_days INT NOT NULL DEFAULT 3 CHECK (delivery_days >= 1 AND delivery_days <= 120),
  revisions INT NOT NULL DEFAULT 1 CHECK (revisions >= 0 AND revisions <= 99),
  is_popular BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (service_id, tier)
);

COMMENT ON TABLE public.service_packages IS
  'Pricing tiers (basic/standard/premium) for marketplace services; the cheapest tier defines the service''s starting price.';

CREATE OR REPLACE FUNCTION public.set_service_packages_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_service_packages_updated_at ON public.service_packages;
CREATE TRIGGER update_service_packages_updated_at
  BEFORE UPDATE ON public.service_packages
  FOR EACH ROW
  EXECUTE FUNCTION public.set_service_packages_updated_at();

-- Keep services.price in sync with the cheapest package.
CREATE OR REPLACE FUNCTION public.sync_services_start_price()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_service_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_service_id := OLD.service_id;
  ELSE
    v_service_id := NEW.service_id;
  END IF;

  UPDATE public.services s
  SET price = COALESCE(
    (SELECT MIN(p.price) FROM public.service_packages p WHERE p.service_id = s.id),
    s.price)
  WHERE s.id = v_service_id;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_service_packages_price_sync ON public.service_packages;
CREATE TRIGGER trigger_service_packages_price_sync
  AFTER INSERT OR UPDATE OR DELETE ON public.service_packages
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_services_start_price();

CREATE INDEX IF NOT EXISTS idx_services_provider_id ON public.services (provider_id);
CREATE INDEX IF NOT EXISTS idx_services_category_id ON public.services (category_id);
CREATE INDEX IF NOT EXISTS idx_services_status ON public.services (status);
CREATE INDEX IF NOT EXISTS idx_service_packages_service_id ON public.service_packages (service_id);

-- ============================================================
-- 3. RLS
-- ============================================================

ALTER TABLE public.service_packages ENABLE ROW LEVEL SECURITY;

-- Browse works signed-out (like products), so the read policy has no role.
DROP POLICY IF EXISTS "Users can view services" ON public.services;
CREATE POLICY "Anyone can view services"
  ON public.services FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Providers can create services" ON public.services;
CREATE POLICY "Providers can create services"
  ON public.services FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = provider_id
    AND (public.is_seller(auth.uid()) OR public.is_service_provider(auth.uid()))
  );

DROP POLICY IF EXISTS "Providers can update own services" ON public.services;
CREATE POLICY "Providers can update own services"
  ON public.services FOR UPDATE TO authenticated
  USING (auth.uid() = provider_id)
  WITH CHECK (auth.uid() = provider_id);

DROP POLICY IF EXISTS "Providers can delete own services" ON public.services;
CREATE POLICY "Providers can delete own services"
  ON public.services FOR DELETE TO authenticated
  USING (auth.uid() = provider_id);

DROP POLICY IF EXISTS "Anyone can read service packages" ON public.service_packages;
CREATE POLICY "Anyone can read service packages"
  ON public.service_packages FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Providers can manage own service packages" ON public.service_packages;
CREATE POLICY "Providers can manage own service packages"
  ON public.service_packages FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.services s
    WHERE s.id = service_id AND s.provider_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.services s
    WHERE s.id = service_id AND s.provider_id = auth.uid()
  ));

-- Realtime for browse refresh + package edits.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'services'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.services;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'service_packages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.service_packages;
  END IF;
END $$;

-- ============================================================
-- 4. Seed service categories
-- ============================================================

INSERT INTO public.categories (name, type, slug) VALUES
  ('Graphic & Design', 'service', 'graphic-design'),
  ('Writing & Translation', 'service', 'writing-translation'),
  ('Digital Marketing', 'service', 'digital-marketing'),
  ('Video & Animation', 'service', 'video-animation'),
  ('Programming & Tech', 'service', 'programming-tech'),
  ('Photography', 'service', 'photography'),
  ('Music & Audio', 'service', 'music-audio'),
  ('Tutoring & Lessons', 'service', 'tutoring-lessons'),
  ('Events & Planning', 'service', 'events-planning'),
  ('Beauty & Wellness', 'service', 'beauty-wellness'),
  ('Repair & Maintenance', 'service', 'repair-maintenance'),
  ('Delivery & Errands', 'service', 'delivery-errands'),
  ('Crafts & Handmade', 'service', 'crafts-handmade'),
  ('Other', 'service', 'other')
ON CONFLICT (name) DO NOTHING;
