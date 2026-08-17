-- Admin topup: credits a user's wallet with admin-specific source
CREATE OR REPLACE FUNCTION public.admin_topup_wallet(
  p_user_id UUID,
  p_amount DECIMAL(12,2),
  p_description TEXT DEFAULT 'Admin balance topup'
)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_wallet RECORD;
  v_ref TEXT;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only admins can perform wallet topups';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Get or create wallet
  INSERT INTO public.wallets (user_id, balance, currency)
  VALUES (p_user_id, 0, 'GHS')
  ON CONFLICT (user_id) DO NOTHING;

  SELECT id, balance INTO v_wallet
  FROM public.wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  v_ref := 'admin_topup_' || extract(epoch from now())::text || '_' || substr(md5(random()::text), 1, 8);

  -- Create transaction
  INSERT INTO public.wallet_transactions (
    wallet_id, type, amount, balance_before, balance_after, description, reference, source
  ) VALUES (
    v_wallet.id, 'deposit', p_amount, v_wallet.balance, v_wallet.balance + p_amount,
    p_description, v_ref, 'admin'
  );

  -- Update balance
  UPDATE public.wallets
  SET balance = balance + p_amount, updated_at = now()
  WHERE id = v_wallet.id;

  -- Notify user
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    p_user_id,
    'Balance Topup',
    'Your wallet has been credited with GH\u00a2 ' || p_amount::TEXT || ' by an administrator.',
    'wallet',
    jsonb_build_object('reference', v_ref, 'amount', p_amount)
  );

  RETURN TRUE;
END;
$$;
