-- Create trigger function to send SMS on wallet transactions
CREATE OR REPLACE FUNCTION public.send_wallet_transaction_sms()
RETURNS TRIGGER AS $$
DECLARE
  v_url TEXT;
  v_anon_key TEXT;
  v_request_id BIGINT;
  v_phone_number TEXT;
  v_full_name TEXT;
  v_sms_content TEXT;
  v_amount_formatted TEXT;
  v_balance_formatted TEXT;
BEGIN
  -- 1. Fetch user phone number and name
  SELECT u.phone_number, u.full_name INTO v_phone_number, v_full_name
  FROM public.users u
  JOIN public.wallets w ON w.user_id = u.id
  WHERE w.id = NEW.wallet_id;

  -- If there's no phone number, we can't send SMS
  IF v_phone_number IS NULL OR v_phone_number = '' THEN
    RETURN NEW;
  END IF;

  -- 2. Normalize phone number (remove non-digits except '+', prepend +233 if starting with 0)
  v_phone_number := regexp_replace(v_phone_number, '[^\d+]', '', 'g');
  IF v_phone_number LIKE '0%' THEN
    v_phone_number := '+233' || substr(v_phone_number, 2);
  ELSIF v_phone_number NOT LIKE '+%' AND v_phone_number <> '' THEN
    v_phone_number := '+' || v_phone_number;
  END IF;

  -- 3. Fetch API keys from config
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_url';
  SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';

  IF v_url IS NULL OR v_anon_key IS NULL THEN
    RAISE LOG 'Wallet transaction SMS trigger: config not set';
    RETURN NEW;
  END IF;

  v_amount_formatted := to_char(NEW.amount, 'FM999,999,990.00');
  v_balance_formatted := to_char(NEW.balance_after, 'FM999,999,990.00');

  -- 4. Construct SMS content based on transaction type
  CASE NEW.type
    WHEN 'deposit' THEN
      v_sms_content := 'Hi ' || v_full_name || ', your wallet has been credited with GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'withdrawal' THEN
      v_sms_content := 'Hi ' || v_full_name || ', your withdrawal of GHS ' || v_amount_formatted || ' has been processed. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'transfer_out' THEN
      v_sms_content := 'Hi ' || v_full_name || ', you have successfully sent GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'transfer_in' THEN
      v_sms_content := 'Hi ' || v_full_name || ', you have received GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'payment' THEN
      v_sms_content := 'Hi ' || v_full_name || ', your payment of GHS ' || v_amount_formatted || ' was successful. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'refund' THEN
      v_sms_content := 'Hi ' || v_full_name || ', you have received a refund of GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    ELSE
      v_sms_content := 'Hi ' || v_full_name || ', a wallet transaction of GHS ' || v_amount_formatted || ' occurred. Type: ' || NEW.type || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '.';
  END CASE;

  -- 5. Invoke Edge Function via pg_net
  SELECT net.http_post(
    url := v_url || '/functions/v1/send-sms',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key
    ),
    body := jsonb_build_object(
      'to', v_phone_number,
      'content', v_sms_content
    )
  ) INTO v_request_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bind the trigger to the wallet_transactions table
DROP TRIGGER IF EXISTS trigger_wallet_transaction_sms ON public.wallet_transactions;
CREATE TRIGGER trigger_wallet_transaction_sms
  AFTER INSERT ON public.wallet_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.send_wallet_transaction_sms();
