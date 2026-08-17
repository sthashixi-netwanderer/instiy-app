-- Fix: mark_item_processing references v_item.buyer_id but only selects from order_items
-- buyer_id lives on orders table, so we need to JOIN like the other RPCs

CREATE OR REPLACE FUNCTION public.mark_item_processing(p_order_item_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_item RECORD;
BEGIN
  SELECT oi.*, o.buyer_id
  INTO v_item
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
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
