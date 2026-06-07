-- Migration to fix order cancellation refund logic and parent order status updates on delivery verification.

-- 1. Redefine verify_delivery to update parent order status to 'delivered' when all items are delivered or cancelled
CREATE OR REPLACE FUNCTION public.verify_delivery(
  p_order_item_id UUID,
  p_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_item RECORD;
  v_amount DECIMAL(12, 2);
  v_result BOOLEAN;
  v_all_delivered BOOLEAN;
BEGIN
  -- Lock and read the order item
  SELECT oi.*, o.buyer_id INTO v_item
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  WHERE oi.id = p_order_item_id
  FOR UPDATE;

  IF v_item.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order item not found');
  END IF;

  IF v_item.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'Order item already ' || v_item.status);
  END IF;

  IF v_item.delivery_code IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'No delivery code set for this item');
  END IF;

  IF upper(trim(v_item.delivery_code)) != upper(trim(p_code)) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Invalid delivery code');
  END IF;

  v_amount := v_item.price * v_item.quantity;

  -- Mark as delivered
  UPDATE public.order_items
  SET status = 'delivered',
      delivery_verified_at = NOW()
  WHERE id = p_order_item_id;

  -- Credit the seller's wallet
  SELECT public.credit_wallet(
    v_item.seller_id,
    v_amount,
    'SALE-' || v_item.order_id || '-' || v_item.id,
    'Verified delivery for order item ' || v_item.id
  ) INTO v_result;

  -- Check if all items in the order are delivered or cancelled
  SELECT NOT EXISTS (
    SELECT 1 FROM public.order_items
    WHERE order_id = v_item.order_id
    AND status NOT IN ('delivered', 'cancelled')
  ) INTO v_all_delivered;

  -- Update parent order status if all items are done
  IF v_all_delivered THEN
    UPDATE public.orders
    SET status = 'delivered', updated_at = NOW()
    WHERE id = v_item.order_id;
  END IF;

  -- Insert notification for buyer
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_item.buyer_id,
    'Delivery Verified',
    'Your item "' || v_item.product_title || '" has been successfully marked as delivered.',
    'delivery',
    jsonb_build_object('order_id', v_item.order_id, 'order_item_id', p_order_item_id)
  );

  -- Insert notification for seller
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_item.seller_id,
    'Delivery Verified & Wallet Credited',
    'Delivery code verified for "' || v_item.product_title || '". GH¢' || v_amount::TEXT || ' has been credited to your wallet.',
    'delivery',
    jsonb_build_object('order_id', v_item.order_id, 'order_item_id', p_order_item_id)
  );

  IF NOT v_result THEN
    RETURN jsonb_build_object(
      'success', true,
      'warning', 'Item verified but wallet credit failed. Seller may need to contact support.',
      'amount', v_amount
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'amount', v_amount);
END;
$$;


-- 2. Redefine cancel_order to cancel pending order items, handle partial refunds, and update parent order status correctly
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
  v_delivery_fee DECIMAL(12, 2);
BEGIN
  SELECT buyer_id, payment_status, delivery_fee
  INTO v_buyer_id, v_payment_status, v_delivery_fee
  FROM public.orders WHERE id = order_id;

  IF v_buyer_id IS NULL THEN
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

  -- Insert notification for each seller of pending/cancelled items
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
