-- Update transfer_wallet_funds to create in-app notifications for both sender and recipient
CREATE OR REPLACE FUNCTION public.transfer_wallet_funds(
  recipient_id UUID,
  amount DECIMAL,
  description TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL,
  p_recipient_name TEXT DEFAULT NULL,
  p_sender_name TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_sender_wallet_id UUID;
  v_sender_balance DECIMAL(12, 2);
  v_recipient_wallet_id UUID;
  v_recipient_balance DECIMAL(12, 2);
  v_pending DECIMAL(12, 2);
  v_ref TEXT;
  v_sender_desc TEXT;
  v_recipient_desc TEXT;
  v_sender_name TEXT;
BEGIN
  SELECT id, balance INTO v_sender_wallet_id, v_sender_balance
  FROM public.wallets WHERE user_id = auth.uid()
  FOR UPDATE;

  IF v_sender_wallet_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT COALESCE(SUM(amount_requested), 0) INTO v_pending
  FROM public.withdrawal_requests
  WHERE user_id = auth.uid() AND status IN ('pending', 'processing');

  IF (v_sender_balance - v_pending) < amount THEN
    RETURN FALSE;
  END IF;

  SELECT id, balance INTO v_recipient_wallet_id, v_recipient_balance
  FROM public.wallets WHERE user_id = recipient_id
  FOR UPDATE;

  IF v_recipient_wallet_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Generate reference if not provided
  v_ref := COALESCE(p_reference, 'TFR-' || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 12)));

  -- Use passed sender name or look up from DB
  v_sender_name := COALESCE(p_sender_name, (SELECT full_name FROM public.users WHERE id = auth.uid()));

  -- Format descriptions with counterparty names
  IF description IS NOT NULL AND description != '' THEN
    v_sender_desc := 'To: ' || COALESCE(p_recipient_name, 'User') || ' - ' || description;
    v_recipient_desc := 'From: ' || COALESCE(v_sender_name, 'User') || ' - ' || description;
  ELSE
    v_sender_desc := 'Transfer to ' || COALESCE(p_recipient_name, 'User');
    v_recipient_desc := 'Transfer from ' || COALESCE(v_sender_name, 'User');
  END IF;

  UPDATE public.wallets
  SET balance = balance - amount, updated_at = NOW()
  WHERE id = v_sender_wallet_id;

  UPDATE public.wallets
  SET balance = balance + amount, updated_at = NOW()
  WHERE id = v_recipient_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, type, amount, balance_before, balance_after, description, reference, source)
  VALUES
    (v_sender_wallet_id, 'transfer_out', amount, v_sender_balance, v_sender_balance - amount, v_sender_desc, v_ref, 'transfer'),
    (v_recipient_wallet_id, 'transfer_in', amount, v_recipient_balance, v_recipient_balance + amount, v_recipient_desc, v_ref, 'transfer');

  -- Create in-app notification for receiver
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    recipient_id,
    'Transfer Received',
    'You have received GH¢' || amount::TEXT || ' from ' || COALESCE(v_sender_name, 'User') || '.',
    'transfer_received',
    jsonb_build_object('amount', amount, 'sender_name', v_sender_name, 'reference', v_ref)
  );

  -- Create in-app notification for sender
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    auth.uid(),
    'Transfer Sent',
    'You have sent GH¢' || amount::TEXT || ' to ' || COALESCE(p_recipient_name, 'User') || '.',
    'transfer_sent',
    jsonb_build_object('amount', amount, 'recipient_name', p_recipient_name, 'reference', v_ref)
  );

  RETURN TRUE;
END;
$$;
