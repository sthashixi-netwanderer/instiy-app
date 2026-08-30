-- SMS punctuation fixes: the SMS channel (GSM-7) has no em dash or cedi
-- sign, so they arrived on handsets as "?".
--  * become_seller SMS: "ready — open the app" -> "ready. Open the app"
--  * send_wallet_transaction_sms: "GH₵" -> "GHS" (cedi sign not in GSM-7)
-- Email and in-app copy are UTF-8 channels and keep their typographic
-- punctuation.

CREATE OR REPLACE FUNCTION public.become_seller(
  p_business_name text,
  p_description text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_was_seller boolean;
  v_full_name text;
  v_email text;
  v_phone text;
  v_url text;
  v_anon_key text;
  v_notify_secret text;
  v_request_id bigint;
  v_subject text;
  v_html text;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in';
  END IF;
  IF p_business_name IS NULL OR length(btrim(p_business_name)) < 2 THEN
    RAISE EXCEPTION 'Business name must be at least 2 characters';
  END IF;

  SELECT u.is_seller, u.full_name, u.email, u.phone_number
    INTO v_was_seller, v_full_name, v_email, v_phone
  FROM public.users u
  WHERE u.id = auth.uid();

  INSERT INTO public.business_profiles (seller_id, business_name, description)
  VALUES (auth.uid(), btrim(p_business_name), NULLIF(btrim(COALESCE(p_description, '')), ''))
  ON CONFLICT (seller_id) DO UPDATE
    SET business_name = EXCLUDED.business_name,
        description   = EXCLUDED.description,
        updated_at    = now();

  UPDATE public.users
  SET is_seller = true, updated_at = now()
  WHERE id = auth.uid() AND NOT is_seller;

  IF v_was_seller THEN
    RETURN; -- already a seller: profile update only, no notifications
  END IF;

  -- 1. In-app notification (the on_notification_created trigger pushes it).
  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    auth.uid(),
    'You''re now a seller on Instiy',
    'Your seller account is ready. Open your dashboard to add listings and set up your store.',
    'system',
    jsonb_build_object('kind', 'become_seller', 'business_name', btrim(p_business_name))
  );

  -- Edge Function config. NOTE: supabase_functions_url is the DIRECT Edge
  -- Functions URL (supabase_url points at the Cloudflare worker, whose auth
  -- rejects the publishable key).
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_functions_url';
  SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';
  SELECT value INTO v_notify_secret FROM public._push_trigger_config WHERE key = 'notify_secret';
  IF v_url IS NULL OR v_anon_key IS NULL OR v_notify_secret IS NULL THEN
    RAISE LOG 'become_seller notifications: _push_trigger_config not set';
    RETURN;
  END IF;

  -- 2. SMS (only when a phone number is on file).
  IF v_phone IS NOT NULL AND v_phone <> '' THEN
    v_phone := regexp_replace(v_phone, '[^\d+]', '', 'g');
    IF v_phone LIKE '0%' THEN
      v_phone := '+233' || substr(v_phone, 2);
    ELSIF v_phone NOT LIKE '+%' AND v_phone <> '' THEN
      v_phone := '+' || v_phone;
    END IF;

    SELECT net.http_post(
      url := v_url || '/functions/v1/send-sms',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon_key
      ),
      body := jsonb_build_object(
        'to', v_phone,
        'content', 'Hi ' || COALESCE(NULLIF(v_full_name, ''), 'there') ||
                   ', you are now a seller on Instiy! Your seller dashboard is ready. Open the app to add your first listing. Thank you for selling with us!'
      )
    ) INTO v_request_id;
  END IF;

  -- 3. Email (x-notify-secret authorizes the server-to-server path).
  IF v_email IS NOT NULL AND v_email <> '' THEN
    v_subject := 'Welcome to selling on Instiy';
    v_html :=
      $html$<!DOCTYPE html>
<html>
<head>
  <title>Welcome to selling on Instiy</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .store { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 16px; }
    .step { margin: 10px 0; color: #44403c; font-size: 14px; line-height: 1.5; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>You're a Seller Now!</h1>
    </div>
    <div class="body">
      <p>Hi $html$ || COALESCE(NULLIF(v_full_name, ''), 'there') || $html$,</p>
      <p class="store">Your Instiy account is now a seller account for "<strong>$html$ || btrim(p_business_name) || $html$</strong>".</p>
      <p>Here's how to get started:</p>
      <div class="step">1. Open your seller dashboard from the bottom navigation.</div>
      <div class="step">2. Add your first product or service listing.</div>
      <div class="step">3. Get verified to earn a badge buyers trust (optional).</div>
      <p style="color: #78716c; font-size: 13px;">Earnings from sales land in your Instiy wallet.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>$html$;

    SELECT net.http_post(
      url := v_url || '/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon_key,
        'x-notify-secret', v_notify_secret
      ),
      body := jsonb_build_object(
        'to', v_email,
        'subject', v_subject,
        'html', v_html
      )
    ) INTO v_request_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.send_wallet_transaction_sms()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_functions_url';
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
$function$
