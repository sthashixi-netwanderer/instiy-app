-- Allows sellers to verify an item's delivery by providing just the 6-character
-- delivery code without needing the order_item_id beforehand.
-- The RPC resolves the calling seller's matching item and invokes verify_delivery().

CREATE OR REPLACE FUNCTION public.verify_delivery_by_code(
  p_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller UUID := auth.uid();
  v_item_id UUID;
  v_result JSONB;
BEGIN
  IF v_seller IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF p_code IS NULL OR trim(p_code) = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Delivery code is required');
  END IF;

  -- 1. Look for pending or processing items for this seller with matching code
  SELECT oi.id INTO v_item_id
  FROM public.order_items oi
  WHERE oi.seller_id = v_seller
    AND upper(trim(oi.delivery_code)) = upper(trim(p_code))
    AND oi.status IN ('pending', 'processing')
  ORDER BY oi.created_at DESC
  LIMIT 1;

  IF v_item_id IS NULL THEN
    -- Check if it belongs to seller but was already delivered
    IF EXISTS (
      SELECT 1 FROM public.order_items oi
      WHERE oi.seller_id = v_seller
        AND upper(trim(oi.delivery_code)) = upper(trim(p_code))
        AND oi.status = 'delivered'
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'This item has already been delivered');
    END IF;

    -- Check if it belongs to seller but was cancelled
    IF EXISTS (
      SELECT 1 FROM public.order_items oi
      WHERE oi.seller_id = v_seller
        AND upper(trim(oi.delivery_code)) = upper(trim(p_code))
        AND oi.status = 'cancelled'
    ) THEN
      RETURN jsonb_build_object('success', false, 'error', 'This order item was cancelled');
    END IF;

    RETURN jsonb_build_object('success', false, 'error', 'Invalid delivery code or item does not belong to your store');
  END IF;

  RETURN public.verify_delivery(v_item_id, p_code);
END;
$$;
