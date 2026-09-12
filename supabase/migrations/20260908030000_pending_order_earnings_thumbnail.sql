-- Add product_id and product_thumbnail to get_pending_order_earnings RPC
-- so the wallet screen can display the product thumbnail and support
-- confirming delivery (scan QR / manual delivery code entry).

DROP FUNCTION IF EXISTS public.get_pending_order_earnings(UUID);

CREATE OR REPLACE FUNCTION public.get_pending_order_earnings(p_user_id UUID)
RETURNS TABLE (
  order_item_id UUID,
  order_id UUID,
  product_id UUID,
  product_title TEXT,
  product_thumbnail TEXT,
  amount DECIMAL(12, 2),
  created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    oi.id AS order_item_id,
    oi.order_id,
    oi.product_id,
    oi.product_title,
    COALESCE(
      oi.product_thumbnail,
      p.thumbnail_url,
      CASE WHEN array_length(p.image_urls, 1) > 0 THEN p.image_urls[1] ELSE NULL END
    ) AS product_thumbnail,
    (oi.price * oi.quantity
      + CASE WHEN o.delivery_mode = 'delivery' THEN COALESCE(
          (SELECT pid.delivery_fee
           FROM public.product_institution_deliveries pid
           WHERE pid.product_id = oi.product_id
             AND pid.institution_name = o.delivery_institution
           LIMIT 1),
          p.delivery_fee,
          0
        ) ELSE 0 END)::DECIMAL(12, 2) AS amount,
    oi.created_at
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  LEFT JOIN public.products p ON p.id = oi.product_id
  WHERE oi.seller_id = p_user_id
    AND o.payment_status = 'paid'
    AND oi.status = 'pending'
  ORDER BY oi.created_at DESC;
$$;
