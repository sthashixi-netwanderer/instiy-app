-- Restoring product stock on order cancellation.
--
-- place_order_with_items decrements products.stock_quantity (and auto-marks
-- the product 'sold' when it reaches zero), but neither cancel path returned
-- that quantity: customer-driven cancel_order and seller-driven
-- cancel_seller_order_item refunded wallets and flipped item statuses only,
-- leaving cancelled stock permanently deducted. Both now return the cancelled
-- quantity to the product and re-list products that were auto-marked 'sold'.

CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  v_buyer_id UUID;
  v_payment_status TEXT;
  v_total_refund DECIMAL(12, 2);
  v_seller_id UUID;
  v_any_delivered BOOLEAN;
  v_any_processing BOOLEAN;
  v_delivery_fee DECIMAL(12, 2);
BEGIN
  SELECT o.buyer_id, o.payment_status, o.delivery_fee
  INTO v_buyer_id, v_payment_status, v_delivery_fee
  FROM public.orders AS o
  WHERE o.id = p_order_id;

  IF v_buyer_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Check if any items are already processing (cannot cancel).
  SELECT EXISTS (
    SELECT 1
    FROM public.order_items AS oi
    WHERE oi.order_id = p_order_id
      AND oi.status = 'processing'
  ) INTO v_any_processing;

  IF v_any_processing THEN
    RETURN FALSE;
  END IF;

  -- Check if any items are already delivered.
  SELECT EXISTS (
    SELECT 1
    FROM public.order_items AS oi
    WHERE oi.order_id = p_order_id
      AND oi.status = 'delivered'
  ) INTO v_any_delivered;

  -- Refund only pending items. Delivery is refunded when no item was delivered.
  SELECT COALESCE(SUM(oi.price * oi.quantity), 0)
  INTO v_total_refund
  FROM public.order_items AS oi
  WHERE oi.order_id = p_order_id
    AND oi.status = 'pending';

  IF NOT v_any_delivered THEN
    v_total_refund := v_total_refund + COALESCE(v_delivery_fee, 0);
  END IF;

  -- Cancel the pending items and return their quantity to stock (products
  -- auto-marked 'sold' at zero go back on sale). Keyed on the rows this
  -- statement flips, so repeated calls never double-restock.
  WITH cancelled_items AS (
    UPDATE public.order_items AS oi
    SET status = 'cancelled'
    WHERE oi.order_id = p_order_id
      AND oi.status = 'pending'
    RETURNING oi.product_id, oi.quantity
  ), restocked AS (
    SELECT product_id, SUM(quantity) AS qty
    FROM cancelled_items
    GROUP BY product_id
  )
  UPDATE public.products AS p
  SET stock_quantity = p.stock_quantity + restocked.qty,
      status = CASE WHEN p.status = 'sold' THEN 'available' ELSE p.status END
  FROM restocked
  WHERE p.id = restocked.product_id;

  -- Refund the buyer if paid and there is an amount to refund.
  IF v_payment_status = 'paid' AND v_total_refund > 0 THEN
    PERFORM public.credit_wallet(
      v_buyer_id,
      v_total_refund,
      'REFUND-' || p_order_id,
      'Refund for cancelled order ' || p_order_id
    );
  END IF;

  -- If all items are cancelled, cancel/refund the parent order. Otherwise
  -- an order with delivered items is considered delivered.
  IF NOT EXISTS (
    SELECT 1
    FROM public.order_items AS oi
    WHERE oi.order_id = p_order_id
      AND oi.status != 'cancelled'
  ) THEN
    UPDATE public.orders AS o
    SET status = 'cancelled',
        payment_status = 'refunded',
        updated_at = NOW()
    WHERE o.id = p_order_id;
  ELSE
    UPDATE public.orders AS o
    SET status = 'delivered',
        updated_at = NOW()
    WHERE o.id = p_order_id;
  END IF;

  -- Notify the buyer.
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_buyer_id,
    'Order Cancelled',
    'Your order has been cancelled.'
      || CASE
           WHEN v_payment_status = 'paid' AND v_total_refund > 0
           THEN ' A refund of GH¢' || v_total_refund::TEXT || ' has been credited to your wallet.'
           ELSE ''
         END,
    'order',
    jsonb_build_object('order_id', p_order_id)
  );

  -- Notify sellers whose pending items were cancelled.
  FOR v_seller_id IN
    SELECT DISTINCT oi.seller_id
    FROM public.order_items AS oi
    WHERE oi.order_id = p_order_id
      AND oi.status = 'cancelled'
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_seller_id,
      'Order Cancelled',
      'An item in order ' || p_order_id || ' has been cancelled.',
      'order',
      jsonb_build_object('order_id', p_order_id)
    );
  END LOOP;

  RETURN TRUE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_seller_order_item(p_order_item_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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

  -- Return the cancelled quantity to the product's stock; products that
  -- place_order_with_items auto-marked 'sold' at zero go back on sale.
  UPDATE public.products AS p
  SET stock_quantity = p.stock_quantity + v_item.quantity,
      status = CASE WHEN p.status = 'sold' THEN 'available' ELSE p.status END
  WHERE p.id = v_item.product_id;

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
$function$;
