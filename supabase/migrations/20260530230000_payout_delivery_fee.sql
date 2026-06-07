-- Redefine verify_delivery to credit delivery_fee to seller's wallet and use the product name in description
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
  v_delivery_fee DECIMAL(12, 2) := 0;
BEGIN
  -- Lock and read the order item
  SELECT oi.*, o.buyer_id, o.delivery_mode, o.delivery_institution
  INTO v_item
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

  -- Add delivery fee to seller wallet credit if delivery mode is delivery
  IF v_item.delivery_mode = 'delivery' THEN
    SELECT COALESCE(
      (SELECT pid.delivery_fee 
       FROM public.product_institution_deliveries pid 
       WHERE pid.product_id = v_item.product_id 
         AND pid.institution_name = v_item.delivery_institution
       LIMIT 1),
      p.delivery_fee,
      0
    ) INTO v_delivery_fee
    FROM public.products p
    WHERE p.id = v_item.product_id;
    
    v_amount := v_amount + v_delivery_fee;
  END IF;

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
    'Verified delivery for "' || v_item.product_title || '"'
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


-- Redefine complete_seller_order_item to credit delivery_fee to seller's wallet and use the product name in description
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
  v_delivery_fee DECIMAL(12, 2) := 0;
BEGIN
  -- Lock and read the order item
  SELECT oi.*, o.buyer_id, o.id AS parent_order_id, o.delivery_mode, o.delivery_institution
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

  -- Add delivery fee to seller wallet credit if delivery mode is delivery
  IF v_item.delivery_mode = 'delivery' THEN
    SELECT COALESCE(
      (SELECT pid.delivery_fee 
       FROM public.product_institution_deliveries pid 
       WHERE pid.product_id = v_item.product_id 
         AND pid.institution_name = v_item.delivery_institution
       LIMIT 1),
      p.delivery_fee,
      0
    ) INTO v_delivery_fee
    FROM public.products p
    WHERE p.id = v_item.product_id;
    
    v_amount := v_amount + v_delivery_fee;
  END IF;

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
    'Delivery confirmed for "' || v_item.product_title || '"'
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


-- Retroactively update old transaction descriptions to show the product name instead of the order item UUID
UPDATE public.wallet_transactions wt
SET description = 'Verified delivery for "' || oi.product_title || '"'
FROM public.order_items oi
WHERE (wt.description LIKE 'Verified delivery for order item %' OR wt.description LIKE 'Delivery confirmed for order item %')
  AND split_part(wt.reference, '-', 3) = oi.id::text;
