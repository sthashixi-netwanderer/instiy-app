-- Add seller_id to order_items for tracking seller ownership
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS seller_id UUID REFERENCES public.users(id);

-- Add delivery_verified_at timestamp
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS delivery_verified_at TIMESTAMP WITH TIME ZONE;

-- Allow sellers to view their order items
DROP POLICY IF EXISTS "Sellers can view their order items" ON public.order_items;
CREATE POLICY "Sellers can view their order items"
  ON public.order_items FOR SELECT
  TO authenticated
  USING (seller_id = auth.uid());

-- Allow sellers to view orders containing their items
DROP POLICY IF EXISTS "Sellers can view orders with their items" ON public.orders;
CREATE POLICY "Sellers can view orders with their items"
  ON public.orders FOR SELECT
  TO authenticated
  USING (id IN (
    SELECT order_id FROM public.order_items WHERE seller_id = auth.uid()
  ));

-- Place order with items as JSONB (cart is in local storage, not user_carts table)
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
BEGIN
  -- Calculate total and count
  SELECT
    COALESCE(SUM((item->>'price')::DECIMAL * (item->>'quantity')::INTEGER), 0),
    COALESCE(SUM((item->>'quantity')::INTEGER), 0)
  INTO v_total, v_item_count
  FROM jsonb_array_elements(p_items) AS item;

  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'No items to order';
  END IF;

  -- Create order
  INSERT INTO public.orders
    (buyer_id, total_amount, item_quantity_total, delivery_mode, payment_method, payment_reference, status, payment_status)
  VALUES
    (p_buyer_id, v_total, v_item_count, p_delivery_mode, p_payment_method, p_payment_reference, 'pending', 'paid')
  RETURNING id INTO v_order_id;

  -- For each item, generate a 6-char alphanumeric code and insert
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
    v_seller_id := (v_item->>'seller_id')::UUID;

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

  -- Return order with items and their delivery codes
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

-- Verify delivery: validate code, mark delivered, credit seller
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
    'Delivery confirmed: ' || v_item.product_title || ' x' || v_item.quantity
  ) INTO v_result;

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

-- Get pending seller earnings (unverified order items total)
CREATE OR REPLACE FUNCTION public.get_pending_seller_earnings(p_user_id UUID)
RETURNS DECIMAL
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_total DECIMAL(12, 2);
BEGIN
  SELECT COALESCE(SUM(oi.price * oi.quantity), 0)
  INTO v_total
  FROM public.order_items oi
  JOIN public.orders o ON o.id = oi.order_id
  WHERE oi.seller_id = p_user_id
    AND oi.status = 'pending'
    AND oi.delivery_code IS NOT NULL;

  RETURN v_total;
END;
$$;
