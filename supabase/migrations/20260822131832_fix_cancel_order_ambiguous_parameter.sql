-- Fix cancel_order parameter/column ambiguity.
-- The previous parameter name (order_id) conflicted with order_items.order_id
-- in PL/pgSQL statements executed by the admin Orders page.

DROP FUNCTION IF EXISTS public.cancel_order(UUID);

CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
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

  -- Update pending items to cancelled.
  UPDATE public.order_items AS oi
  SET status = 'cancelled'
  WHERE oi.order_id = p_order_id
    AND oi.status = 'pending';

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
$$;
