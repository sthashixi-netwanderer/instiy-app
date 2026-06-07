-- Migration: Add is_featured column to products table
-- Allows admin to mark products as featured for the home screen carousel.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_featured BOOLEAN DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_products_is_featured ON public.products(is_featured) WHERE is_featured = true;

-- RPC function: get top products by order count (best sellers)
CREATE OR REPLACE FUNCTION public.get_best_seller_products(p_limit INTEGER DEFAULT 10)
RETURNS SETOF public.products
LANGUAGE sql STABLE
AS $$
  SELECT p.*
  FROM public.products p
  JOIN public.order_items oi ON oi.product_id = p.id
  WHERE p.status = 'available'
  GROUP BY p.id
  ORDER BY COUNT(oi.id) DESC, p.created_at DESC
  LIMIT p_limit;
$$;

-- RPC function: get trending products (most ordered in last 7 days)
CREATE OR REPLACE FUNCTION public.get_trending_products(p_limit INTEGER DEFAULT 10)
RETURNS SETOF public.products
LANGUAGE sql STABLE
AS $$
  SELECT p.*
  FROM public.products p
  LEFT JOIN public.order_items oi ON oi.product_id = p.id
    AND oi.created_at >= NOW() - INTERVAL '7 days'
  WHERE p.status = 'available'
  GROUP BY p.id
  ORDER BY COUNT(oi.id) DESC, p.created_at DESC
  LIMIT p_limit;
$$;
