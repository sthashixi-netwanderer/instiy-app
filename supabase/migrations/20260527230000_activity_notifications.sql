-- 1. Update place_order_with_items to include notifications for buyer and sellers
CREATE OR REPLACE FUNCTION public.place_order_with_items(
  p_buyer_id UUID,
  p_items JSONB,
  p_delivery_mode TEXT DEFAULT 'pickup',
  p_payment_method TEXT DEFAULT 'wallet',
  p_payment_reference TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_order_id UUID;
  v_total DECIMAL(12, 2);
  v_item_count INTEGER;
  v_item JSONB;
  v_code TEXT;
  v_seller_id UUID;
  v_delivery_fee DECIMAL(12, 2) := 0;
BEGIN
  -- Calculate subtotal and count
  SELECT
    COALESCE(SUM((item->>'price')::DECIMAL * (item->>'quantity')::INTEGER), 0),
    COALESCE(SUM((item->>'quantity')::INTEGER), 0)
  INTO v_total, v_item_count
  FROM jsonb_array_elements(p_items) AS item;

  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'No items to order';
  END IF;

  -- Calculate delivery fee if mode is delivery
  IF p_delivery_mode = 'delivery' THEN
    SELECT COALESCE(SUM(p.delivery_fee), 0) INTO v_delivery_fee
    FROM (
      SELECT DISTINCT (value->>'product_id')::UUID as product_id
      FROM jsonb_array_elements(p_items)
    ) items
    JOIN public.products p ON p.id = items.product_id;
  END IF;

  -- Create order with total_amount including delivery_fee
  INSERT INTO public.orders
    (buyer_id, total_amount, item_quantity_total, delivery_mode, delivery_fee, payment_method, payment_reference, status, payment_status)
  VALUES
    (p_buyer_id, v_total + v_delivery_fee, v_item_count, p_delivery_mode, v_delivery_fee, p_payment_method, p_payment_reference, 'pending', 'paid')
  RETURNING id INTO v_order_id;

  -- For each item, generate a code, decrement stock, and insert
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    v_seller_id := (v_item->>'seller_id')::UUID;

    -- Decrement stock and update status if out of stock
    UPDATE public.products
    SET stock_quantity = GREATEST(0, stock_quantity - (v_item->>'quantity')::INTEGER),
        status = CASE WHEN (stock_quantity - (v_item->>'quantity')::INTEGER) <= 0 THEN 'sold' ELSE status END
    WHERE id = (v_item->>'product_id')::UUID;

    INSERT INTO public.order_items
      (order_id, product_id, product_title, product_thumbnail, quantity, price, delivery_code, status, seller_id)
    VALUES
      (v_order_id,
       (v_item->>'product_id')::UUID,
       v_item->>'product_title',
       v_item->>'product_thumbnail',
       (v_item->>'quantity')::INTEGER,
       (v_item->>'price')::DECIMAL,
       v_code,
       'pending',
       v_seller_id);
  END LOOP;

  -- Insert notification for buyer
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    p_buyer_id,
    'Order Placed Successfully',
    'Your order has been placed successfully! Total: GH¢' || (v_total + v_delivery_fee)::TEXT,
    'order',
    jsonb_build_object('order_id', v_order_id)
  );

  -- Insert notification for each seller
  FOR v_seller_id IN
    SELECT DISTINCT seller_id FROM public.order_items WHERE order_id = v_order_id
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_seller_id,
      'New Order Received',
      'You have received a new order!',
      'order',
      jsonb_build_object('order_id', v_order_id)
    );
  END LOOP;

  -- Return order details
  RETURN (
    SELECT jsonb_build_object(
      'order_id', v_order_id,
      'items', (
        SELECT jsonb_agg(jsonb_build_object(
          'id', oi.id,
          'product_id', oi.product_id,
          'product_title', oi.product_title,
          'quantity', oi.quantity,
          'price', oi.price,
          'delivery_code', oi.delivery_code,
          'seller_id', oi.seller_id
        ))
        FROM public.order_items oi
        WHERE oi.order_id = v_order_id
      )
    )
  );
END;
$$;


-- 2. Update verify_delivery to include notifications for buyer and seller
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
    -- Wallet credit failed, but order is still verified
    RETURN jsonb_build_object(
      'success', true,
      'warning', 'Item verified but wallet credit failed. Seller may need to contact support.',
      'amount', v_amount
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'amount', v_amount);
END;
$$;


-- 3. Update cancel_order to include notifications for buyer and sellers
CREATE OR REPLACE FUNCTION public.cancel_order(order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_buyer_id UUID;
  v_total DECIMAL(12, 2);
  v_payment_status TEXT;
  v_seller_id UUID;
BEGIN
  SELECT buyer_id, total_amount, payment_status
  INTO v_buyer_id, v_total, v_payment_status
  FROM public.orders WHERE id = order_id;

  IF v_buyer_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF v_payment_status = 'paid' THEN
    PERFORM public.credit_wallet(v_buyer_id, v_total, 'REFUND-' || order_id, 'Refund for cancelled order ' || order_id);
  END IF;

  UPDATE public.orders
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = order_id;

  -- Insert notification for buyer
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_buyer_id,
    'Order Cancelled',
    'Your order has been cancelled.' || CASE WHEN v_payment_status = 'paid' THEN ' A refund of GH¢' || v_total::TEXT || ' has been credited to your wallet.' ELSE '' END,
    'order',
    jsonb_build_object('order_id', order_id)
  );

  -- Insert notification for each seller
  FOR v_seller_id IN
    SELECT DISTINCT seller_id FROM public.order_items WHERE order_id = order_id
  LOOP
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_seller_id,
      'Order Cancelled',
      'Order ' || order_id || ' has been cancelled.',
      'order',
      jsonb_build_object('order_id', order_id)
    );
  END LOOP;

  RETURN TRUE;
END;
$$;
