-- Add stock_quantity, delivery_option, and delivery_fee to products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS stock_quantity INTEGER DEFAULT 1 NOT NULL;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS delivery_option TEXT DEFAULT 'pickup' NOT NULL CHECK (delivery_option IN ('pickup', 'delivery', 'both'));
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS delivery_fee DECIMAL(10, 2) DEFAULT 0 NOT NULL;

-- Constraint: if delivery_option is 'pickup', delivery_fee must be 0
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS chk_product_delivery_fee;
ALTER TABLE public.products ADD CONSTRAINT chk_product_delivery_fee CHECK (
  (delivery_option = 'pickup' AND delivery_fee = 0) OR
  (delivery_option IN ('delivery', 'both'))
);

-- Update place_order_with_items to include delivery fee and decrement stock quantity
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
