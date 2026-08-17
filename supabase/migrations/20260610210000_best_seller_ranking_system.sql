-- Best-Seller Ranking System
-- Hybrid scoring: sales velocity (time-decay) + profit margin + out-of-stock penalty
-- Materialized view refreshed daily at 3 AM via pg_cron

-- 1. Add cost_price column for margin calculations
ALTER TABLE public.products
ADD COLUMN IF NOT EXISTS cost_price NUMERIC(10,2);

COMMENT ON COLUMN public.products.cost_price IS 'Seller cost price for margin calculations. NULL means unknown.';

-- 2. Add index on order_items.product_id (missing from original schema)
CREATE INDEX IF NOT EXISTS idx_order_items_product_id
ON public.order_items (product_id);

-- 3. Enable pg_cron and pg_net extensions
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- 4. Materialized View: mv_best_seller_rankings
CREATE MATERIALIZED VIEW public.mv_best_seller_rankings AS
WITH params AS (
  SELECT
    60 AS decay_days,
    0.6 AS weight_sales,
    0.4 AS weight_margin
),
sales_data AS (
  SELECT
    oi.product_id,
    COUNT(oi.id) AS total_orders,
    COALESCE(SUM(oi.quantity), 0) AS total_units_sold,
    COALESCE(SUM(oi.price * oi.quantity), 0) AS gross_revenue,
    MAX(oi.created_at) AS last_sale_at,
    SUM(
      EXP(-LN(2) * EXTRACT(EPOCH FROM (NOW() - oi.created_at)) / (60 * 86400))
    ) AS weighted_score
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  WHERE o.status NOT IN ('cancelled', 'refunded')
  GROUP BY oi.product_id
),
scored AS (
  SELECT
    sd.product_id,
    sd.total_orders,
    sd.total_units_sold,
    sd.gross_revenue,
    sd.last_sale_at,
    sd.weighted_score,
    CASE
      WHEN MAX(sd.weighted_score) OVER () > 0
      THEN (sd.weighted_score / MAX(sd.weighted_score) OVER ()) * 100
      ELSE 0
    END AS sales_score,
    CASE
      WHEN p.cost_price IS NOT NULL AND p.cost_price > 0
      THEN LEAST(((p.price - p.cost_price) / p.price) * 100, 100)
      ELSE 50
    END AS margin_score,
    CASE
      WHEN p.stock_quantity <= 0 THEN 0.5
      ELSE 1.0
    END AS stock_multiplier
  FROM sales_data sd
  JOIN public.products p ON p.id = sd.product_id
  WHERE p.status = 'available'
)
SELECT
  s.product_id,
  s.total_orders,
  s.total_units_sold,
  s.gross_revenue,
  s.last_sale_at,
  s.sales_score,
  s.margin_score,
  s.stock_multiplier,
  ROUND(
    (((s.sales_score * p.weight_sales) + (s.margin_score * p.weight_margin))
    * s.stock_multiplier)::numeric,
    2
  ) AS hybrid_score,
  DENSE_RANK() OVER (ORDER BY
    ((s.sales_score * p.weight_sales) + (s.margin_score * p.weight_margin))
    * s.stock_multiplier
  DESC) AS global_rank,
  DENSE_RANK() OVER (PARTITION BY pr.category_id ORDER BY
    ((s.sales_score * p.weight_sales) + (s.margin_score * p.weight_margin))
    * s.stock_multiplier
  DESC) AS category_rank,
  NOW() AS refreshed_at
FROM scored s
CROSS JOIN params p
JOIN public.products pr ON pr.id = s.product_id
WITH NO DATA;

-- Unique index required for CONCURRENTLY refresh
CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_best_seller_rankings_product_id
ON public.mv_best_seller_rankings (product_id);

CREATE INDEX IF NOT EXISTS idx_mv_best_seller_rankings_global_rank
ON public.mv_best_seller_rankings (global_rank);

CREATE INDEX IF NOT EXISTS idx_mv_best_seller_rankings_category_rank
ON public.mv_best_seller_rankings (category_rank);

-- 5. Refresh function
CREATE OR REPLACE FUNCTION public.refresh_best_seller_rankings()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY public.mv_best_seller_rankings;
END;
$$;

-- 6. Schedule daily refresh at 3 AM
SELECT cron.schedule(
  'refresh-best-sellers-daily',
  '0 3 * * *',
  $$SELECT public.refresh_best_seller_rankings()$$
);

-- 7. Replace RPC: get_best_seller_products (now queries materialized view)
CREATE OR REPLACE FUNCTION public.get_best_seller_products(
  p_limit INTEGER DEFAULT 10,
  p_category_id UUID DEFAULT NULL
)
RETURNS TABLE (
  id UUID,
  seller_id UUID,
  title TEXT,
  description TEXT,
  price NUMERIC(10,2),
  image_urls TEXT[],
  category_id UUID,
  condition TEXT,
  status TEXT,
  campus TEXT,
  stock_quantity INTEGER,
  delivery_fee NUMERIC(10,2),
  slug TEXT,
  is_featured BOOLEAN,
  created_at TIMESTAMPTZ,
  hybrid_score NUMERIC,
  global_rank INTEGER,
  category_rank INTEGER,
  total_orders BIGINT,
  total_units_sold BIGINT
)
LANGUAGE sql STABLE
AS $$
  SELECT
    p.id, p.seller_id, p.title, p.description, p.price,
    p.image_urls, p.category_id, p.condition, p.status,
    p.campus, p.stock_quantity, p.delivery_fee, p.slug,
    p.is_featured, p.created_at,
    mv.hybrid_score, mv.global_rank, mv.category_rank,
    mv.total_orders, mv.total_units_sold
  FROM public.mv_best_seller_rankings mv
  JOIN public.products p ON p.id = mv.product_id
  WHERE p.status = 'available'
    AND (p_category_id IS NULL OR p.category_id = p_category_id)
  ORDER BY mv.hybrid_score DESC
  LIMIT p_limit;
$$;
