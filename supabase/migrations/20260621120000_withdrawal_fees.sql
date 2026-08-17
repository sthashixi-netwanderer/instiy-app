-- Migration: Withdrawal Fee System
-- Creates platform_settings table and updates process_withdrawal_request RPC

-- 1. Create platform_settings table
CREATE TABLE IF NOT EXISTS public.platform_settings (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Insert default fee config (2% mobile money, 1% bank)
INSERT INTO public.platform_settings (key, value) VALUES
('withdrawal_fees', '{"mobile_money": 0.02, "bank": 0.01}'::jsonb)
ON CONFLICT (key) DO NOTHING;

-- 3. RLS: everyone reads, admin writes
ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read platform_settings" ON public.platform_settings;
CREATE POLICY "Anyone can read platform_settings"
  ON public.platform_settings FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Admins can manage platform_settings" ON public.platform_settings;
CREATE POLICY "Admins can manage platform_settings"
  ON public.platform_settings FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- 4. Grant access
GRANT SELECT ON public.platform_settings TO authenticated;
GRANT ALL ON public.platform_settings TO service_role;

-- 5. Update process_withdrawal_request RPC to use fee columns
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
  v_fee DECIMAL(12, 2);
  v_payout DECIMAL(12, 2);
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

  -- Backfill fee columns for old pending requests that have NULL fees
  IF v_request.fee_amount IS NULL OR v_request.amount_to_receive IS NULL THEN
    -- Default fallback: 2% fee
    v_fee := ROUND(v_request.amount_requested * 0.02, 2);
    v_payout := v_request.amount_requested - v_fee;

    UPDATE public.withdrawal_requests
    SET fee_amount = v_fee,
        amount_to_receive = v_payout
    WHERE id = p_request_id;

    v_request.fee_amount := v_fee;
    v_request.amount_to_receive := v_payout;
  ELSE
    v_fee := v_request.fee_amount;
    v_payout := v_request.amount_to_receive;
  END IF;

  -- If completing the withdrawal, deduct wallet balance
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

    -- Deduct full amount_requested from wallet (user pays full, platform keeps fee)
    UPDATE public.wallets
    SET balance = balance - v_request.amount_requested,
        updated_at = NOW()
    WHERE id = v_wallet_id;

    -- Insert wallet transaction with fee breakdown in description
    INSERT INTO public.wallet_transactions
      (wallet_id, type, amount, balance_before, balance_after, description, reference, source)
    VALUES
      (v_wallet_id, 'withdrawal', v_request.amount_requested, v_balance, v_balance - v_request.amount_requested,
       'Withdrawal processed — Fee: GH₵' || v_fee::TEXT || ' | Payout: GH₵' || v_payout::TEXT,
       v_request.id::text, 'wallet');
  END IF;

  -- Update withdrawal request status
  UPDATE public.withdrawal_requests
  SET status = p_status,
      admin_notes = p_admin_notes
  WHERE id = p_request_id;

  RETURN TRUE;
END;
$$;
