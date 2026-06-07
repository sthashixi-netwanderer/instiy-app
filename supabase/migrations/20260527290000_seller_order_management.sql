-- Seller completes an order item (delivers to buyer, credits seller wallet)
CREATE OR REPLACE FUNCTION public.complete_seller_order_item(
  p_order_item_id UUID
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_item RECORD;
  v_amount DECIMAL(12, 2);
  v_credit_result BOOLEAN;
  v_all_delivered BOOLEAN;
BEGIN
  -- Lock and read the order item
  SELECT oi.*, o.buyer_id, o.id AS parent_order_id
  INTO v_item
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  WHERE oi.id = p_order_item_id
  FOR UPDATE;

  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order item not found');
  END IF;

  -- Verify the caller is the seller
  IF v_item.seller_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'You are not the seller of this item');
  END IF;

  IF v_item.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Item already ' || v_item.status);
  END IF;

  v_amount := v_item.price * v_item.quantity;

  -- Mark item as delivered
  UPDATE public.order_items
  SET status = 'delivered',
      delivery_verified_at = NOW()
  WHERE id = p_order_item_id;

  -- Credit the seller's wallet
  SELECT public.credit_wallet(
    v_item.seller_id,
    v_amount,
    'SALE-' || v_item.parent_order_id || '-' || v_item.id,
    'Delivery confirmed: ' || v_item.product_title || ' x' || v_item.quantity
  ) INTO v_credit_result;

  -- Check if all items in the order are delivered
  SELECT NOT EXISTS (
    SELECT 1 FROM public.order_items
    WHERE order_id = v_item.parent_order_id
    AND status NOT IN ('delivered', 'cancelled')
  ) INTO v_all_delivered;

  -- Update parent order status if all items are done
  IF v_all_delivered THEN
    UPDATE public.orders
    SET status = 'delivered', updated_at = NOW()
    WHERE id = v_item.parent_order_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'amount', v_amount,
    'wallet_credited', v_credit_result
  );
END;
$$;

-- Seller cancels an order item (refunds buyer proportionally)
CREATE OR REPLACE FUNCTION public.cancel_seller_order_item(
  p_order_item_id UUID,
  p_reason TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_item RECORD;
  v_refund_amount DECIMAL(12, 2);
  v_refund_result BOOLEAN;
  v_all_cancelled BOOLEAN;
  v_any_active BOOLEAN;
  v_reason_text TEXT;
BEGIN
  -- Lock and read the order item
  SELECT oi.*, o.buyer_id, o.id AS parent_order_id
  INTO v_item
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  WHERE oi.id = p_order_item_id
  FOR UPDATE;

  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order item not found');
  END IF;

  -- Verify the caller is the seller
  IF v_item.seller_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'You are not the seller of this item');
  END IF;

  IF v_item.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Item already ' || v_item.status);
  END IF;

  v_refund_amount := v_item.price * v_item.quantity;
  v_reason_text := COALESCE(p_reason, 'No reason provided');

  -- Mark item as cancelled
  UPDATE public.order_items
  SET status = 'cancelled'
  WHERE id = p_order_item_id;

  -- Refund the buyer (include reason in description)
  SELECT public.credit_wallet(
    v_item.buyer_id,
    v_refund_amount,
    'ITEM-REFUND-' || v_item.parent_order_id || '-' || v_item.id,
    'Refund for cancelled item: ' || v_item.product_title || '. Reason: ' || v_reason_text
  ) INTO v_refund_result;

  -- Check if all items are cancelled
  SELECT NOT EXISTS (
    SELECT 1 FROM public.order_items
    WHERE order_id = v_item.parent_order_id
    AND status != 'cancelled'
  ) INTO v_all_cancelled;

  IF v_all_cancelled THEN
    UPDATE public.orders
    SET status = 'cancelled', payment_status = 'refunded', updated_at = NOW()
    WHERE id = v_item.parent_order_id;
  ELSE
    -- Check if any active (non-cancelled) items remain
    SELECT EXISTS (
      SELECT 1 FROM public.order_items
      WHERE order_id = v_item.parent_order_id
      AND status NOT IN ('cancelled', 'delivered')
    ) INTO v_any_active;

    IF NOT v_any_active THEN
      -- All items are either delivered or cancelled — order is done
      UPDATE public.orders
      SET status = 'delivered', updated_at = NOW()
      WHERE id = v_item.parent_order_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'refund_amount', v_refund_amount,
    'buyer_refunded', v_refund_result
  );
END;
$$;
