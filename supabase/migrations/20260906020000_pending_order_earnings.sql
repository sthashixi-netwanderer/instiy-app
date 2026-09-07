-- Pending balance covers more than withdrawal holds: paid order items
-- awaiting delivery verification are escrowed earnings for the seller and
-- are surfaced (itemized) in the wallet next to pending withdrawals.

-- Itemized escrowed earnings. Mirrors the payout amount computed by
-- verify_delivery / complete_seller_order_item: price * quantity, plus the
-- per-product delivery fee when the order is a delivery (both credited
-- together once delivery is verified). Delivered items are already in the
-- wallet; unpaid or cancelled items are not owed.
CREATE OR REPLACE FUNCTION public.get_pending_order_earnings(p_user_id UUID)
RETURNS TABLE (
  order_item_id UUID,
  order_id UUID,
  product_title TEXT,
  amount DECIMAL(12, 2),
  created_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT
    oi.id,
    oi.order_id,
    oi.product_title,
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
  JOIN public.products p ON p.id = oi.product_id
  WHERE oi.seller_id = p_user_id
    AND o.payment_status = 'paid'
    AND oi.status = 'pending'
  ORDER BY oi.created_at DESC;
$$;

-- The wallet provider listens for order_item changes on the seller's items
-- so pending earnings update live as deliveries are verified.
ALTER PUBLICATION supabase_realtime ADD TABLE public.order_items;
