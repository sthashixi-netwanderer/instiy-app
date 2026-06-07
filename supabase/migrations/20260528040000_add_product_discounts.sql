-- Add discount fields to products table
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS discount_percent NUMERIC(5,2) DEFAULT 0,
ADD COLUMN IF NOT EXISTS discount_start_date DATE,
ADD COLUMN IF NOT EXISTS discount_end_date DATE;

-- Index for filtering active discounts
CREATE INDEX IF NOT EXISTS idx_products_discount
  ON public.products (discount_percent, discount_end_date)
  WHERE discount_percent > 0;

-- Function to check if a discount is currently active
CREATE OR REPLACE FUNCTION public.is_discount_active(
  p_discount_percent NUMERIC,
  p_discount_start_date DATE,
  p_discount_end_date DATE
)
RETURNS BOOLEAN
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
  IF p_discount_percent IS NULL OR p_discount_percent <= 0 THEN
    RETURN FALSE;
  END IF;
  IF p_discount_start_date IS NOT NULL AND p_discount_start_date > CURRENT_DATE THEN
    RETURN FALSE;
  END IF;
  IF p_discount_end_date IS NOT NULL AND p_discount_end_date < CURRENT_DATE THEN
    RETURN FALSE;
  END IF;
  RETURN TRUE;
END;
$$;

-- Function to calculate discounted price
CREATE OR REPLACE FUNCTION public.get_discounted_price(
  p_price NUMERIC,
  p_discount_percent NUMERIC,
  p_discount_start_date DATE,
  p_discount_end_date DATE
)
RETURNS NUMERIC
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
  IF public.is_discount_active(p_discount_percent, p_discount_start_date, p_discount_end_date) THEN
    RETURN ROUND(p_price * (1 - p_discount_percent / 100), 2);
  END IF;
  RETURN p_price;
END;
$$;
