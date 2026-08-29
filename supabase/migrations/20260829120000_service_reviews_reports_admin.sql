-- Service reviews, service reports (with image evidence), and admin
-- management access for the services marketplace.
--
-- 1. service_reviews: one review per (service, reviewer) with a stats
--    trigger keeping services.average_rating / review_count accurate.
-- 2. reports: service_id + evidence media_urls columns, two new service
--    report categories, and a no-self-report policy.
-- 3. get_admin_reports(): extended with service context and evidence URLs.
-- 4. Admin RLS over services / service_packages / service_reviews so the
--    admin panel can moderate the marketplace.

-- ============================================================
-- 1. Service reviews
-- ============================================================

CREATE TABLE IF NOT EXISTS public.service_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id UUID NOT NULL REFERENCES public.services(id) ON DELETE CASCADE,
  reviewer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  rating INT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  helpful_count INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (service_id, reviewer_id)
);

COMMENT ON TABLE public.service_reviews IS
  'Customer reviews for marketplace services; one per (service, reviewer), stats rolled up onto services.';

CREATE OR REPLACE FUNCTION public.set_service_reviews_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS update_service_reviews_updated_at ON public.service_reviews;
CREATE TRIGGER update_service_reviews_updated_at
  BEFORE UPDATE ON public.service_reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.set_service_reviews_updated_at();

-- Keep the denormalized rating columns accurate on every write.
CREATE OR REPLACE FUNCTION public.sync_service_review_stats()
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
  SET average_rating = COALESCE(
    (SELECT ROUND(AVG(r.rating)::numeric, 2) FROM public.service_reviews r WHERE r.service_id = s.id),
    0),
    review_count = (SELECT count(*) FROM public.service_reviews r WHERE r.service_id = s.id)
  WHERE s.id = v_service_id;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_service_reviews_stats ON public.service_reviews;
CREATE TRIGGER trigger_service_reviews_stats
  AFTER INSERT OR UPDATE OR DELETE ON public.service_reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_service_review_stats();

CREATE INDEX IF NOT EXISTS idx_service_reviews_service_id ON public.service_reviews (service_id);
CREATE INDEX IF NOT EXISTS idx_service_reviews_reviewer_id ON public.service_reviews (reviewer_id);

ALTER TABLE public.service_reviews ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read service reviews" ON public.service_reviews;
CREATE POLICY "Anyone can read service reviews"
  ON public.service_reviews FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can review services" ON public.service_reviews;
CREATE POLICY "Users can review services"
  ON public.service_reviews FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = reviewer_id);

DROP POLICY IF EXISTS "Reviewers can update own service reviews" ON public.service_reviews;
CREATE POLICY "Reviewers can update own service reviews"
  ON public.service_reviews FOR UPDATE TO authenticated
  USING (auth.uid() = reviewer_id)
  WITH CHECK (auth.uid() = reviewer_id);

DROP POLICY IF EXISTS "Reviewers can delete own service reviews" ON public.service_reviews;
CREATE POLICY "Reviewers can delete own service reviews"
  ON public.service_reviews FOR DELETE TO authenticated
  USING (auth.uid() = reviewer_id);

-- ============================================================
-- 2. Reports: service context + image evidence
-- ============================================================

ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS service_id UUID REFERENCES public.services(id) ON DELETE CASCADE;
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS media_urls TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_reports_service ON public.reports (service_id);

-- Expand the category CHECK with service-specific reasons.
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_category_check;

ALTER TABLE public.reports ADD CONSTRAINT reports_category_check CHECK (category IN (
  -- User report categories
  'spam', 'harassment', 'scam', 'inappropriate_content',
  'fake_account', 'hate_speech', 'violence', 'illegal_activity',
  -- Product report categories
  'counterfeit', 'misleading_listing', 'prohibited_item',
  'product_scam', 'stolen_property', 'price_gouging',
  -- Service report categories
  'service_scam', 'misleading_service',
  'other'
));

-- Providers cannot report their own services.
DROP POLICY IF EXISTS "Users cannot report own services" ON public.reports;
CREATE POLICY "Users cannot report own services"
  ON public.reports FOR INSERT TO authenticated
  WITH CHECK (
    service_id IS NULL OR
    service_id NOT IN (
      SELECT s.id FROM public.services s WHERE s.provider_id = auth.uid()
    )
  );

-- ============================================================
-- 3. get_admin_reports(): service fields + evidence
-- ============================================================

-- Return type changed (service/evidence columns): replace via DROP.
DROP FUNCTION IF EXISTS public.get_admin_reports();

CREATE OR REPLACE FUNCTION public.get_admin_reports()
RETURNS TABLE (
  report_id UUID,
  reporter_id UUID,
  reporter_name TEXT,
  reporter_avatar TEXT,
  reporter_university TEXT,
  reported_user_id UUID,
  reported_name TEXT,
  reported_avatar TEXT,
  reported_university TEXT,
  reported_suspended BOOLEAN,
  category TEXT,
  description TEXT,
  evidence_urls TEXT[],
  conversation_id UUID,
  product_id UUID,
  product_title TEXT,
  product_image TEXT,
  product_price NUMERIC,
  service_id UUID,
  service_title TEXT,
  service_image TEXT,
  service_price NUMERIC,
  service_status TEXT,
  status TEXT,
  admin_notes TEXT,
  is_read BOOLEAN,
  complaint_id UUID,
  complaint_text TEXT,
  complaint_status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN QUERY
  SELECT
    r.id AS report_id,
    r.reporter_id,
    rp.full_name AS reporter_name,
    rp.avatar_url AS reporter_avatar,
    rp.university AS reporter_university,
    r.reported_user_id,
    rup.full_name AS reported_name,
    rup.avatar_url AS reported_avatar,
    rup.university AS reported_university,
    COALESCE(rup.suspended, FALSE) AS reported_suspended,
    r.category,
    r.description,
    r.media_urls AS evidence_urls,
    r.conversation_id,
    r.product_id,
    p.title AS product_title,
    CASE
      WHEN p.image_urls IS NOT NULL AND array_length(p.image_urls, 1) > 0 THEN p.image_urls[1]
      ELSE NULL
    END AS product_image,
    p.price AS product_price,
    r.service_id,
    s.title AS service_title,
    CASE
      WHEN s.image_urls IS NOT NULL AND array_length(s.image_urls, 1) > 0 THEN s.image_urls[1]
      ELSE NULL
    END AS service_image,
    s.price AS service_price,
    s.status AS service_status,
    r.status,
    r.admin_notes,
    r.is_read,
    uc.id AS complaint_id,
    uc.complaint_text,
    uc.status AS complaint_status,
    r.created_at,
    r.updated_at
  FROM public.reports r
  JOIN public.users rp ON rp.id = r.reporter_id
  JOIN public.users rup ON rup.id = r.reported_user_id
  LEFT JOIN public.products p ON p.id = r.product_id
  LEFT JOIN public.services s ON s.id = r.service_id
  LEFT JOIN public.user_complaints uc ON uc.report_id = r.id
  ORDER BY r.created_at DESC;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.get_admin_reports() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.get_admin_reports() TO authenticated;

-- ============================================================
-- 4. Admin management access for the services marketplace
-- ============================================================

DROP POLICY IF EXISTS "Admins can manage services" ON public.services;
CREATE POLICY "Admins can manage services"
  ON public.services FOR ALL TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can manage service packages" ON public.service_packages;
CREATE POLICY "Admins can manage service packages"
  ON public.service_packages FOR ALL TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can manage service reviews" ON public.service_reviews;
CREATE POLICY "Admins can manage service reviews"
  ON public.service_reviews FOR ALL TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- ============================================================
-- 5. Realtime for reviews
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'service_reviews'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.service_reviews;
  END IF;
END $$;
