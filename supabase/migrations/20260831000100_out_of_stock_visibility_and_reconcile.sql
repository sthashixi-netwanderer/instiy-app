-- Out-of-stock visibility + cancelled-stock reconciliation.
--
-- Products whose whole stock is tied up in a pending-delivery order are
-- marked 'sold' with stock 0 by place_order_with_items and must stay hidden
-- from every storefront feed until the order is cancelled (which restores
-- the stock) or the seller restocks. The Explore query already filtered on
-- status + stock; these changes close the remaining paths and repair the
-- data stranded by the pre-fix cancel behaviour.

-- Storefront RPCs: exclude zero-stock products alongside the status filter.
CREATE OR REPLACE FUNCTION public.get_best_seller_products(p_limit integer DEFAULT 10)
 RETURNS SETOF products
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.*
  FROM public.products p
  JOIN public.order_items oi ON oi.product_id = p.id
  WHERE p.status = 'available'
    AND p.stock_quantity > 0
  GROUP BY p.id
  ORDER BY COUNT(oi.id) DESC, p.created_at DESC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.get_best_seller_products(p_limit integer DEFAULT 10, p_category_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(id uuid, seller_id uuid, title text, description text, price numeric, image_urls text[], category_id uuid, condition text, status text, campus text, stock_quantity integer, delivery_fee numeric, slug text, is_featured boolean, created_at timestamp with time zone, hybrid_score numeric, global_rank integer, category_rank integer, total_orders bigint, total_units_sold bigint)
 LANGUAGE sql
 STABLE
AS $function$
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
    AND p.stock_quantity > 0
    AND (p_category_id IS NULL OR p.category_id = p_category_id)
  ORDER BY mv.hybrid_score DESC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.get_trending_products(p_limit integer DEFAULT 10)
 RETURNS SETOF products
 LANGUAGE sql
 STABLE
AS $function$
  SELECT p.*
  FROM public.products p
  LEFT JOIN order_items oi ON oi.product_id = p.id
    AND oi.created_at >= NOW() - INTERVAL '7 days'
  WHERE p.status = 'available'
    AND p.stock_quantity > 0
  GROUP BY p.id
  ORDER BY COUNT(oi.id) DESC, p.created_at DESC
  LIMIT p_limit;
$function$;

-- One-time reconciliation: orders cancelled before the stock-restore fix
-- left their quantity permanently deducted, pinning products at 'sold'/0.
-- Return those quantities and re-list the products.
WITH stranded AS (
  SELECT p.id,
         p.stock_quantity + COALESCE(SUM(oi.quantity), 0) AS restored_stock
  FROM public.products p
  JOIN public.order_items oi
    ON oi.product_id = p.id AND oi.status = 'cancelled'
  WHERE p.status = 'sold' AND p.stock_quantity = 0
  GROUP BY p.id, p.stock_quantity
)
UPDATE public.products p
SET stock_quantity = stranded.restored_stock,
    status = 'available'
FROM stranded
WHERE p.id = stranded.id;
