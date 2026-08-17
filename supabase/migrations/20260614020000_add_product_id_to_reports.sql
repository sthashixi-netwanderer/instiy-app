-- ============================================================
-- Fix: Ensure product_id column exists on reports table
-- The earlier product_reports migration was not applied to
-- the remote database, so get_admin_reports() fails.
-- ============================================================

-- Add product_id column (safe if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'reports' AND column_name = 'product_id'
  ) THEN
    ALTER TABLE public.reports
      ADD COLUMN product_id UUID REFERENCES public.products(id) ON DELETE CASCADE;
    CREATE INDEX IF NOT EXISTS idx_reports_product ON public.reports(product_id);
  END IF;
END $$;

-- Ensure the expanded category CHECK constraint includes product categories
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_category_check;

ALTER TABLE public.reports ADD CONSTRAINT reports_category_check CHECK (category IN (
  'spam', 'harassment', 'scam', 'inappropriate_content',
  'fake_account', 'hate_speech', 'violence', 'illegal_activity',
  'counterfeit', 'misleading_listing', 'prohibited_item',
  'product_scam', 'stolen_property', 'price_gouging',
  'other'
));
