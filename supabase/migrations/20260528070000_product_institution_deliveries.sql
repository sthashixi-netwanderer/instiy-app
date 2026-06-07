-- Create product_institution_deliveries table for per-institution delivery fees
CREATE TABLE IF NOT EXISTS public.product_institution_deliveries (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  institution_name TEXT NOT NULL,
  delivery_fee DECIMAL(10,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(product_id, institution_name)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_product_institution_deliveries_product_id
  ON public.product_institution_deliveries(product_id);

-- Enable RLS
ALTER TABLE public.product_institution_deliveries ENABLE ROW LEVEL SECURITY;

-- Policies: product owners manage, anyone can view
DROP POLICY IF EXISTS "Product owners manage institution deliveries" ON public.product_institution_deliveries;
CREATE POLICY "Product owners manage institution deliveries"
  ON public.product_institution_deliveries FOR ALL
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.products
      WHERE products.id = product_id AND products.seller_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Anyone can view institution deliveries" ON public.product_institution_deliveries;
CREATE POLICY "Anyone can view institution deliveries"
  ON public.product_institution_deliveries FOR SELECT
  USING (true);
