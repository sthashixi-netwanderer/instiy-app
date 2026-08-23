-- Notify the user when they become a seller: in-app notification (which the
-- on_notification_created trigger fans out as a push), SMS, and email.
--
-- Replaces become_seller() with a version that fires all three only on the
-- actual false -> true transition (idempotent re-runs just update the
-- business profile and stay silent). SMS/email ride the same pg_net ->
-- Edge Function pattern as the wallet transaction SMS trigger, using the
-- supabase_url / anon_key rows in _push_trigger_config.

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

  -- Edge Function config (same source as the wallet SMS trigger).
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_url';
  SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';
  IF v_url IS NULL OR v_anon_key IS NULL THEN
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
                   ', you are now a seller on Instiy! Your seller dashboard is ready — open the app to add your first listing. Thank you for selling with us!'
      )
    ) INTO v_request_id;
  END IF;

  -- 3. Email.
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
        'Authorization', 'Bearer ' || v_anon_key
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
