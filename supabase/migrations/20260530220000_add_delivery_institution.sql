-- Add delivery_institution column to orders
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_institution TEXT;

-- Update place_order_with_items function to support p_delivery_institution
CREATE OR REPLACE FUNCTION public.place_order_with_items(
  p_buyer_id UUID,
  p_items JSONB,
  p_delivery_mode TEXT DEFAULT 'pickup',
  p_payment_method TEXT DEFAULT 'wallet',
  p_payment_reference TEXT DEFAULT NULL,
  p_delivery_institution TEXT DEFAULT NULL
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
    SELECT COALESCE(SUM(
      COALESCE(
        (SELECT pid.delivery_fee 
         FROM public.product_institution_deliveries pid 
         WHERE pid.product_id = items.product_id 
           AND pid.institution_name = p_delivery_institution
         LIMIT 1),
        p.delivery_fee,
        0
      )
    ), 0) INTO v_delivery_fee
    FROM (
      SELECT DISTINCT (value->>'product_id')::UUID as product_id
      FROM jsonb_array_elements(p_items)
    ) items
    JOIN public.products p ON p.id = items.product_id;
  END IF;

  -- Create order with total_amount including delivery_fee and delivery_institution
  INSERT INTO public.orders
    (buyer_id, total_amount, item_quantity_total, delivery_mode, delivery_fee, payment_method, payment_reference, status, payment_status, delivery_institution)
  VALUES
    (p_buyer_id, v_total + v_delivery_fee, v_item_count, p_delivery_mode, v_delivery_fee, p_payment_method, p_payment_reference, 'pending', 'paid', p_delivery_institution)
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
