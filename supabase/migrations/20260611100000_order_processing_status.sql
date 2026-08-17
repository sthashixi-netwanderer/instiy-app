-- Add 'processing' status for order items and update cancel_order to block cancellation when processing.

-- 1. RPC: Mark an order item as 'processing' (pending -> processing only)
CREATE OR REPLACE FUNCTION public.mark_item_processing(p_order_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_item RECORD;
BEGIN
  SELECT oi.* INTO v_item
  FROM public.order_items oi
  WHERE oi.id = p_order_item_id
  FOR UPDATE;

  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order item not found');
  END IF;

  IF v_item.seller_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'You are not the seller of this item');
  END IF;

  IF v_item.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Only pending items can be marked as processing. Current status: ' || v_item.status);
  END IF;

  UPDATE public.order_items
  SET status = 'processing'
  WHERE id = p_order_item_id;

  -- Insert notification for buyer
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_item.buyer_id,
    'Order Processing',
    'Your item "' || v_item.product_title || '" is now being prepared for delivery.',
    'order',
    jsonb_build_object('order_id', v_item.order_id, 'order_item_id', p_order_item_id)
  );

  RETURN jsonb_build_object('success', true);
END;
$$;

-- 2. Update cancel_order: refuse cancellation if any items are 'processing'
CREATE OR REPLACE FUNCTION public.cancel_order(order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_buyer_id UUID;
  v_payment_status TEXT;
  v_total_refund DECIMAL(12, 2);
  v_seller_id UUID;
  v_any_delivered BOOLEAN;
  v_any_processing BOOLEAN;
  v_delivery_fee DECIMAL(12, 2);
BEGIN
  SELECT buyer_id, payment_status, delivery_fee
  INTO v_buyer_id, v_payment_status, v_delivery_fee
  FROM public.orders WHERE id = order_id;

  IF v_buyer_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Check if any items are already processing (cannot cancel)
  SELECT EXISTS (
    SELECT 1 FROM public.order_items
    WHERE order_id = cancel_order.order_id AND status = 'processing'
  ) INTO v_any_processing;

  IF v_any_processing THEN
    RETURN FALSE;
  END IF;

  -- Check if any items are already delivered
  SELECT EXISTS (
    SELECT 1 FROM public.order_items
    WHERE order_id = cancel_order.order_id AND status = 'delivered'
  ) INTO v_any_delivered;

  -- Calculate total refund amount: sum of (price * quantity) of all pending items
  SELECT COALESCE(SUM(price * quantity), 0) INTO v_total_refund
  FROM public.order_items
  WHERE order_id = cancel_order.order_id AND status = 'pending';

  -- If no items are delivered yet, we also refund the delivery fee
  IF NOT v_any_delivered THEN
    v_total_refund := v_total_refund + COALESCE(v_delivery_fee, 0);
  END IF;

  -- Update pending items to cancelled
  UPDATE public.order_items
  SET status = 'cancelled'
  WHERE order_id = cancel_order.order_id AND status = 'pending';

  -- Refund the buyer if paid and we have a refund amount
  IF v_payment_status = 'paid' AND v_total_refund > 0 THEN
    PERFORM public.credit_wallet(v_buyer_id, v_total_refund, 'REFUND-' || order_id, 'Refund for cancelled order ' || order_id);
  END IF;

  -- Update parent order status:
  -- If all items in the order are now cancelled, the status of order is cancelled and payment_status is refunded
  -- If some items were delivered, the status of order is delivered
  IF NOT EXISTS (
    SELECT 1 FROM public.order_items
    WHERE order_id = cancel_order.order_id AND status != 'cancelled'
  ) THEN
    UPDATE public.orders
    SET status = 'cancelled', payment_status = 'refunded', updated_at = NOW()
    WHERE id = order_id;
  ELSE
    UPDATE public.orders
    SET status = 'delivered', updated_at = NOW()
    WHERE id = order_id;
  END IF;

  -- Insert notification for buyer
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_buyer_id,
    'Order Cancelled',
    'Your order has been cancelled.' || CASE WHEN v_payment_status = 'paid' AND v_total_refund > 0 THEN ' A refund of GH¢' || v_total_refund::TEXT || ' has been credited to your wallet.' ELSE '' END,
    'order',
    jsonb_build_object('order_id', order_id)
  );

  -- Insert notification for each seller of cancelled items
  FOR v_seller_id IN
    SELECT DISTINCT seller_id FROM public.order_items WHERE order_id = cancel_order.order_id AND status = 'cancelled'
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_seller_id,
      'Order Cancelled',
      'An item in order ' || order_id || ' has been cancelled.',
      'order',
      jsonb_build_object('order_id', order_id)
    );
  END LOOP;

  RETURN TRUE;
END;
$$;
