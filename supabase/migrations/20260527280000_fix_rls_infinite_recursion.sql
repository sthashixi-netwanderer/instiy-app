-- =============================================================
-- Fix: RLS infinite recursion on order_items / orders
--
-- The recursion loop was:
--   "Users can view own order items" → subquery on orders → triggers orders RLS
--   "Sellers can view orders with their items" → subquery on order_items → triggers order_items RLS
--   → infinite loop (code 42P17)
--
-- Fix: replace cross-table subquery policies with direct column checks.
-- order_items already has both buyer_id (via the order) and seller_id columns.
-- We use a SECURITY DEFINER helper to safely read orders.buyer_id without RLS.
-- =============================================================

-- 1. Helper: get the buyer_id for an order_item without triggering RLS
--    SECURITY DEFINER bypasses RLS on orders, breaking the recursion.
CREATE OR REPLACE FUNCTION public.get_order_buyer_id(p_order_id UUID)
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT buyer_id FROM public.orders WHERE id = p_order_id;
$$;

-- 2. Drop the recursive "Users can view own order items" policy
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;

-- 3. Replace it: buyers see items where they are the order buyer (no cross-table RLS trigger)
CREATE POLICY "Buyers can view own order items"
  ON public.order_items FOR SELECT
  TO authenticated
  USING (public.get_order_buyer_id(order_id) = auth.uid());

-- 4. Drop the recursive "Sellers can view orders with their items" policy on orders
DROP POLICY IF EXISTS "Sellers can view orders with their items" ON public.orders;

-- 5. Replace it: sellers see orders where ANY of their items exist
--    Uses a SECURITY DEFINER function to avoid recursion back into order_items RLS.
CREATE OR REPLACE FUNCTION public.seller_has_item_in_order(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.order_items
    WHERE order_id = p_order_id AND seller_id = auth.uid()
  );
$$;

CREATE POLICY "Sellers can view orders with their items"
  ON public.orders FOR SELECT
  TO authenticated
  USING (public.seller_has_item_in_order(id));
