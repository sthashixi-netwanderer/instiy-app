-- ============================================================
-- Phase 1: Server-Side Aggregations
-- ============================================================

-- 1. Product ratings aggregation RPC
-- Replaces client-side review fetching + average computation in product_service.dart
CREATE OR REPLACE FUNCTION public.get_product_ratings(p_product_ids UUID[])
RETURNS TABLE (
  product_id UUID,
  average_rating NUMERIC,
  review_count BIGINT
) AS $$
  SELECT
    pr.product_id,
    ROUND(AVG(pr.rating)::NUMERIC, 1) AS average_rating,
    COUNT(*) AS review_count
  FROM public.product_reviews pr
  WHERE pr.product_id = ANY(p_product_ids)
    AND pr.rating IS NOT NULL
  GROUP BY pr.product_id;
$$ LANGUAGE sql STABLE;

-- 2. Seller dashboard stats RPC
-- Replaces the multi-query + client-side fold/where logic in seller_service.dart getDashboardStats()
CREATE OR REPLACE FUNCTION public.get_seller_dashboard_stats(p_seller_id UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
  v_product_ids UUID[];
BEGIN
  -- Collect seller's product IDs
  SELECT array_agg(p.id) INTO v_product_ids
  FROM public.products p
  WHERE p.seller_id = p_seller_id;

  SELECT json_build_object(
    'totalProducts', COALESCE((
      SELECT SUM(p.stock_quantity)::INT
      FROM public.products p
      WHERE p.seller_id = p_seller_id
    ), 0),
    'activeListings', (
      SELECT COUNT(*)::INT
      FROM public.products p
      WHERE p.seller_id = p_seller_id
        AND p.status = 'available'
    ),
    'averageRating', COALESCE((
      SELECT ROUND(AVG(pr.rating)::NUMERIC, 1)
      FROM public.product_reviews pr
      WHERE pr.product_id = ANY(v_product_ids)
        AND pr.rating IS NOT NULL
    ), 0),
    'newReviews', (
      SELECT COUNT(*)::INT
      FROM public.product_reviews pr
      WHERE pr.product_id = ANY(v_product_ids)
        AND pr.created_at >= NOW() - INTERVAL '7 days'
    ),
    'followersCount', (
      SELECT COUNT(*)::INT
      FROM public.seller_follows sf
      WHERE sf.seller_id = p_seller_id
    ),
    'recentProducts', (
      SELECT COUNT(*)::INT
      FROM public.products p
      WHERE p.seller_id = p_seller_id
        AND p.created_at >= NOW() - INTERVAL '30 days'
    ),
    'pendingOrders', (
      SELECT COUNT(DISTINCT oi.order_id)::INT
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.product_id = ANY(v_product_ids)
        AND o.status NOT IN ('delivered', 'cancelled')
    ),
    'totalSold', COALESCE((
      SELECT SUM(oi.quantity)::INT
      FROM public.order_items oi
      WHERE oi.product_id = ANY(v_product_ids)
    ), 0),
    'totalRevenue', COALESCE((
      SELECT SUM(oi.price * oi.quantity)::NUMERIC
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.product_id = ANY(v_product_ids)
        AND o.payment_status = 'paid'
    ), 0)
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

-- 3. Seller analytics RPC
-- Replaces the multi-query + client-side join in seller_service.dart getAnalytics()
CREATE OR REPLACE FUNCTION public.get_seller_analytics(p_seller_id UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
  v_product_ids UUID[];
BEGIN
  SELECT array_agg(p.id) INTO v_product_ids
  FROM public.products p
  WHERE p.seller_id = p_seller_id;

  SELECT json_build_object(
    'totalOrders', (
      SELECT COUNT(*)::INT
      FROM public.order_items oi
      WHERE oi.product_id = ANY(v_product_ids)
    ),
    'totalEarned', COALESCE((
      SELECT SUM(oi.price * oi.quantity)::NUMERIC
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.product_id = ANY(v_product_ids)
        AND o.payment_status = 'paid'
    ), 0),
    'monthRevenue', COALESCE((
      SELECT SUM(oi.price * oi.quantity)::NUMERIC
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.product_id = ANY(v_product_ids)
        AND o.payment_status = 'paid'
        AND oi.created_at >= NOW() - INTERVAL '30 days'
    ), 0),
    'avgOrderValue', CASE
      WHEN (SELECT COUNT(*) FROM public.order_items oi WHERE oi.product_id = ANY(v_product_ids)) > 0
      THEN (
        SELECT ROUND(SUM(oi.price * oi.quantity) / COUNT(*)::NUMERIC)::INT
        FROM public.order_items oi
        JOIN public.orders o ON o.id = oi.order_id
        WHERE oi.product_id = ANY(v_product_ids)
          AND o.payment_status = 'paid'
      )
      ELSE 0
    END
  ) INTO result;

  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

-- 4. Seller orders RPC
-- Replaces the client-side JOIN of order_items to orders in seller_service.dart getSellerOrders()
CREATE OR REPLACE FUNCTION public.get_seller_orders(p_seller_id UUID)
RETURNS TABLE (
  id UUID,
  buyer_id UUID,
  total_amount NUMERIC,
  delivery_fee NUMERIC,
  item_quantity_total INT,
  status TEXT,
  payment_status TEXT,
  delivery_mode TEXT,
  delivery_institution TEXT,
  created_at TIMESTAMPTZ,
  items JSON
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.id,
    o.buyer_id,
    o.total_amount,
    o.delivery_fee,
    o.item_quantity_total,
    o.status,
    o.payment_status,
    o.delivery_mode,
    o.delivery_institution,
    o.created_at,
    (
      SELECT json_agg(json_build_object(
        'id', oi.id,
        'order_id', oi.order_id,
        'product_id', oi.product_id,
        'product_title', oi.product_title,
        'product_thumbnail', oi.product_thumbnail,
        'quantity', oi.quantity,
        'price', oi.price,
        'delivery_code', oi.delivery_code,
        'status', oi.status
      ))
      FROM public.order_items oi
      WHERE oi.order_id = o.id
        AND oi.product_id IN (
          SELECT p.id FROM public.products p WHERE p.seller_id = p_seller_id
        )
    ) AS items
  FROM public.orders o
  WHERE o.id IN (
    SELECT DISTINCT oi.order_id
    FROM public.order_items oi
    JOIN public.products p ON p.id = oi.product_id
    WHERE p.seller_id = p_seller_id
  )
  ORDER BY o.created_at DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- ============================================================
-- Phase 3: Index Optimizations
-- ============================================================

-- Composite index for order_items seller queries
CREATE INDEX IF NOT EXISTS idx_order_items_product_order
  ON public.order_items(product_id, order_id);

-- Index for notification filtering
CREATE INDEX IF NOT EXISTS idx_notifications_user_read
  ON public.notifications(user_id, is_read);

CREATE INDEX IF NOT EXISTS idx_notifications_user_type
  ON public.notifications(user_id, type);

-- Composite index for product_reviews aggregation
CREATE INDEX IF NOT EXISTS idx_product_reviews_product_rating
  ON public.product_reviews(product_id, rating)
  WHERE rating IS NOT NULL;

-- Index for seller_follows lookup
CREATE INDEX IF NOT EXISTS idx_seller_follows_seller
  ON public.seller_follows(seller_id);

-- Index for order_items status filtering (used by seller orders)
CREATE INDEX IF NOT EXISTS idx_order_items_status
  ON public.order_items(status);
