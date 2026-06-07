-- Migration: Add Admin Role and Policies for Instiy Admin Panel

-- 1. Add is_admin column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_admin BOOLEAN DEFAULT false;

-- 2. Create is_admin helper function (Security Definer to avoid RLS recursion)
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users
    WHERE id = p_user_id AND is_admin = true
  );
END;
$$;

-- 3. Set up Admin policies on public.users
DROP POLICY IF EXISTS "Admins can view all profiles" ON public.users;
CREATE POLICY "Admins can view all profiles"
  ON public.users FOR SELECT
  TO authenticated
  USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can update any profile" ON public.users;
CREATE POLICY "Admins can update any profile"
  ON public.users FOR UPDATE
  TO authenticated
  USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can delete any profile" ON public.users;
CREATE POLICY "Admins can delete any profile"
  ON public.users FOR DELETE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 4. Set up Admin policies on public.categories
DROP POLICY IF EXISTS "Admins can manage categories" ON public.categories;
CREATE POLICY "Admins can manage categories"
  ON public.categories FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 5. Set up Admin policies on public.products
DROP POLICY IF EXISTS "Admins can manage products" ON public.products;
CREATE POLICY "Admins can manage products"
  ON public.products FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 6. Set up Admin policies on public.orders
DROP POLICY IF EXISTS "Admins can manage orders" ON public.orders;
CREATE POLICY "Admins can manage orders"
  ON public.orders FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 7. Set up Admin policies on public.order_items
DROP POLICY IF EXISTS "Admins can manage order items" ON public.order_items;
CREATE POLICY "Admins can manage order items"
  ON public.order_items FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 8. Set up Admin policies on public.wallets
DROP POLICY IF EXISTS "Admins can manage wallets" ON public.wallets;
CREATE POLICY "Admins can manage wallets"
  ON public.wallets FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 9. Set up Admin policies on public.wallet_transactions
DROP POLICY IF EXISTS "Admins can manage transactions" ON public.wallet_transactions;
CREATE POLICY "Admins can manage transactions"
  ON public.wallet_transactions FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 10. Set up Admin policies on public.withdrawal_requests
DROP POLICY IF EXISTS "Admins can manage withdrawal requests" ON public.withdrawal_requests;
CREATE POLICY "Admins can manage withdrawal requests"
  ON public.withdrawal_requests FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 11. Set up Admin policies on public.product_reviews
DROP POLICY IF EXISTS "Admins can manage reviews" ON public.product_reviews;
CREATE POLICY "Admins can manage reviews"
  ON public.product_reviews FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 12. Set up Admin policies on public.product_review_replies
DROP POLICY IF EXISTS "Admins can manage review replies" ON public.product_review_replies;
CREATE POLICY "Admins can manage review replies"
  ON public.product_review_replies FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 13. Create process_withdrawal_request RPC function
CREATE OR REPLACE FUNCTION public.process_withdrawal_request(
  p_request_id UUID,
  p_status TEXT,
  p_admin_notes TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_request RECORD;
  v_wallet_id UUID;
  v_balance DECIMAL(12, 2);
BEGIN
  -- Lock and read the withdrawal request
  SELECT * INTO v_request
  FROM public.withdrawal_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Withdrawal request not found';
  END IF;

  IF v_request.status NOT IN ('pending', 'processing') THEN
    RAISE EXCEPTION 'Withdrawal request is already %', v_request.status;
  END IF;

  IF p_status NOT IN ('processing', 'completed', 'failed', 'cancelled') THEN
    RAISE EXCEPTION 'Invalid target status %', p_status;
  END IF;

  -- If completing the withdrawal, we deduct the wallet balance
  IF p_status = 'completed' THEN
    -- Find and lock user's wallet
    SELECT id, balance INTO v_wallet_id, v_balance
    FROM public.wallets
    WHERE user_id = v_request.user_id
    FOR UPDATE;

    IF v_wallet_id IS NULL THEN
      RAISE EXCEPTION 'User wallet not found';
    END IF;

    IF v_balance < v_request.amount_requested THEN
      RAISE EXCEPTION 'Insufficient wallet balance to complete this withdrawal';
    END IF;

    -- Update wallet balance
    UPDATE public.wallets
    SET balance = balance - v_request.amount_requested,
        updated_at = NOW()
    WHERE id = v_wallet_id;

    -- Insert wallet transaction
    INSERT INTO public.wallet_transactions
      (wallet_id, type, amount, balance_before, balance_after, description, reference, source)
    VALUES
      (v_wallet_id, 'withdrawal', v_request.amount_requested, v_balance, v_balance - v_request.amount_requested, 
       COALESCE(p_admin_notes, 'Withdrawal processed'), v_request.id::text, 'wallet');
  END IF;

  -- Update withdrawal request status
  UPDATE public.withdrawal_requests
  SET status = p_status,
      admin_notes = p_admin_notes
  WHERE id = p_request_id;

  RETURN TRUE;
END;
$$;

