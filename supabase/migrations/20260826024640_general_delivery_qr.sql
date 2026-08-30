-- General delivery QR: one buyer QR covers all pending purchases; any seller
-- can scan it but only ever sees/verifies their own items for that buyer.
-- The QR itself carries just the buyer id (no delivery codes leak).

CREATE OR REPLACE FUNCTION public.get_buyer_pending_items_for_seller(
  p_buyer_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller UUID := auth.uid();
BEGIN
  IF v_seller IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_buyer_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Buyer not found');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'buyer_name', (SELECT full_name FROM public.users WHERE id = p_buyer_id),
    'items', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', oi.id,
        'order_id', oi.order_id,
        'product_title', oi.product_title,
        'product_thumbnail', oi.product_thumbnail,
        'quantity', oi.quantity,
        'price', oi.price,
        'status', oi.status
      ) ORDER BY oi.created_at DESC)
      FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE o.buyer_id = p_buyer_id
        AND oi.seller_id = v_seller
        AND oi.status IN ('pending', 'processing')
        AND oi.delivery_code IS NOT NULL
    ), '[]'::jsonb)
  );
END;
$$;

-- Verifies one or many of the caller's pending items for a buyer without the
-- seller needing each 6-char code: possession of the buyer's general QR (the
-- buyer id) authorises delivery of the caller's OWN items only. Reuses the
-- existing verify_delivery() logic per item (wallet credit, notifications,
-- order completion check). NULL p_item_ids = every matching item.
CREATE OR REPLACE FUNCTION public.verify_buyer_deliveries(
  p_buyer_id UUID,
  p_item_ids UUID[] DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seller UUID := auth.uid();
  v_item_id UUID;
  v_result JSONB;
  v_verified INT := 0;
  v_total DECIMAL(12, 2) := 0;
  v_errors TEXT[] := '{}';
BEGIN
  IF v_seller IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  FOR v_item_id IN
    SELECT oi.id
    FROM public.order_items oi
    JOIN public.orders o ON o.id = oi.order_id
    WHERE o.buyer_id = p_buyer_id
      AND oi.seller_id = v_seller
      AND oi.status IN ('pending', 'processing')
      AND oi.delivery_code IS NOT NULL
      AND (p_item_ids IS NULL OR oi.id = ANY(p_item_ids))
    ORDER BY oi.created_at
  LOOP
    v_result := public.verify_delivery(
      v_item_id,
      (SELECT delivery_code FROM public.order_items WHERE id = v_item_id)
    );

    IF (v_result ->> 'success')::boolean THEN
      v_verified := v_verified + 1;
      v_total := v_total + COALESCE((v_result ->> 'amount')::decimal, 0);
    ELSE
      v_errors := array_append(v_errors, COALESCE(v_result ->> 'error', 'Verification failed'));
    END IF;
  END LOOP;

  IF v_verified = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', COALESCE(v_errors[1], 'No pending items to deliver for this buyer')
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'verified', v_verified,
    'amount', v_total,
    'warnings', to_jsonb(array_remove(v_errors, NULL))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_buyer_pending_items_for_seller(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_buyer_deliveries(UUID, UUID[]) TO authenticated;
