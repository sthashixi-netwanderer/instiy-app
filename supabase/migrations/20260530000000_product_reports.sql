-- ============================================================
-- Product Reports — Extend reports table for product reporting
-- ============================================================

-- 1. Add product_id column (nullable, preserves existing user-only reports)
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS product_id UUID REFERENCES public.products(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_reports_product ON public.reports(product_id);

-- 2. Drop old category CHECK and add expanded one with product report categories
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_category_check;

ALTER TABLE public.reports ADD CONSTRAINT reports_category_check CHECK (category IN (
  -- User report categories (existing)
  'spam', 'harassment', 'scam', 'inappropriate_content',
  'fake_account', 'hate_speech', 'violence', 'illegal_activity',
  -- Product report categories (new)
  'counterfeit', 'misleading_listing', 'prohibited_item',
  'product_scam', 'stolen_property', 'price_gouging',
  'other'
));

-- 3. RLS: Users cannot report their own products
CREATE POLICY "Users cannot report own products"
  ON public.reports FOR INSERT
  TO authenticated
  WITH CHECK (
    product_id IS NULL OR
    product_id NOT IN (
      SELECT p.id FROM public.products p WHERE p.seller_id = auth.uid()
    )
  );

-- 4. RPC: Get admin reports with product details
CREATE OR REPLACE FUNCTION get_admin_reports()
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
  category TEXT,
  description TEXT,
  conversation_id UUID,
  product_id UUID,
  product_title TEXT,
  product_image TEXT,
  product_price NUMERIC,
  status TEXT,
  admin_notes TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
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
    r.category,
    r.description,
    r.conversation_id,
    r.product_id,
    p.title AS product_title,
    CASE
      WHEN p.images IS NOT NULL AND array_length(p.images, 1) > 0 THEN p.images[1]
      ELSE NULL
    END AS product_image,
    p.price AS product_price,
    r.status,
    r.admin_notes,
    r.created_at,
    r.updated_at
  FROM public.reports r
  JOIN public.users rp ON rp.id = r.reporter_id
  JOIN public.users rup ON rup.id = r.reported_user_id
  LEFT JOIN public.products p ON p.id = r.product_id
  ORDER BY r.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
