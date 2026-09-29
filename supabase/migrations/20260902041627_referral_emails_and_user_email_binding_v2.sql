-- 20260902043000_referral_emails_and_user_email_binding.sql
-- 1. Ensure public.users.email is bound from auth.users on signup and backfilled
-- 2. Send email notification to referrer when a new invite signs up
-- 3. Send email notification to referrer anytime referral points are awarded

-- A. Backfill any missing emails in public.users from auth.users
UPDATE public.users u
SET email = a.email
FROM auth.users a
WHERE u.id = a.id
  AND (u.email IS NULL OR btrim(u.email) = '')
  AND a.email IS NOT NULL;

-- B. Update handle_new_user to ensure email binding and send referral invite email
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  base_tag TEXT;
  final_tag TEXT;
  counter INT := 1;
  tag_exists BOOLEAN;
  v_code TEXT;
  v_code_exists BOOLEAN;
  v_alphabet TEXT := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
  v_ref_code TEXT;
  v_referrer UUID;
  v_referrer_email TEXT;
  v_referrer_name TEXT;
  v_invitee_name TEXT;
  v_email TEXT;
  v_url TEXT;
  v_anon_key TEXT;
  v_notify_secret TEXT;
  v_subject TEXT;
  v_html TEXT;
BEGIN
  -- Resolve email from NEW.email or raw metadata
  v_email := COALESCE(NEW.email, NEW.raw_user_meta_data->>'email');

  -- Prefer user's custom wallet tag if provided and valid (at least 5 characters)
  base_tag := NEW.raw_user_meta_data->>'wallet_tag';

  IF base_tag IS NULL OR length(base_tag) < 5 THEN
    -- Fallback to generating from full_name or email
    base_tag := COALESCE(NEW.raw_user_meta_data->>'full_name', v_email, 'user');
    base_tag := lower(regexp_replace(base_tag, '[^a-zA-Z]', '', 'g'));
    IF length(base_tag) < 5 THEN
      base_tag := rpad(base_tag, 5, 'x');
    END IF;
  ELSE
    base_tag := lower(regexp_replace(base_tag, '[^a-zA-Z0-9]', '', 'g'));
  END IF;

  final_tag := base_tag;

  -- Loop to ensure uniqueness
  LOOP
    SELECT EXISTS(SELECT 1 FROM public.users WHERE wallet_tag = final_tag) INTO tag_exists;
    IF NOT tag_exists THEN
      EXIT;
    END IF;
    final_tag := base_tag || counter::TEXT;
    counter := counter + 1;
  END LOOP;

  -- Generate this user's own unique referral code.
  LOOP
    v_code := '';
    FOR i IN 1..8 LOOP
      v_code := v_code || substr(
        v_alphabet,
        floor(random() * length(v_alphabet))::int + 1,
        1
      );
    END LOOP;
    SELECT EXISTS (
      SELECT 1 FROM public.users WHERE referral_code = v_code
    ) INTO v_code_exists;
    EXIT WHEN NOT v_code_exists;
  END LOOP;

  INSERT INTO public.users (
    id, email, full_name, university, phone_number, wallet_tag, referral_code
  )
  VALUES (
    NEW.id,
    v_email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', v_email, 'Instiy User'),
    NEW.raw_user_meta_data->>'university',
    NEW.raw_user_meta_data->>'phone_number',
    final_tag,
    v_code
  )
  ON CONFLICT (id) DO UPDATE SET
    email = COALESCE(EXCLUDED.email, public.users.email),
    full_name = COALESCE(EXCLUDED.full_name, public.users.full_name),
    university = COALESCE(EXCLUDED.university, public.users.university),
    phone_number = COALESCE(EXCLUDED.phone_number, public.users.phone_number);

  -- Record the referral if a valid code was supplied at signup.
  v_ref_code := upper(trim(COALESCE(NEW.raw_user_meta_data->>'referral_code', '')));
  IF v_ref_code ~ '^[A-Z0-9]{4,32}$' THEN
    SELECT id, email, full_name INTO v_referrer, v_referrer_email, v_referrer_name
    FROM public.users
    WHERE referral_code = v_ref_code
      AND id <> NEW.id;

    IF v_referrer IS NOT NULL THEN
      INSERT INTO public.referrals (referrer_id, referred_id, code_used, status)
      VALUES (v_referrer, NEW.id, v_ref_code, 'registered');

      v_invitee_name := COALESCE(NULLIF(btrim(NEW.raw_user_meta_data->>'full_name'), ''), 'Someone');

      INSERT INTO public.notifications (user_id, title, body, type, data)
      VALUES (
        v_referrer,
        'New Invite Registered! 🎉',
        v_invitee_name || ' just signed up using your referral code (' || v_ref_code || ')!',
        'referral',
        jsonb_build_object(
          'type', 'referral_signup',
          'referred_id', NEW.id,
          'code', v_ref_code
        )
      );

      -- Fallback to auth.users if public.users.email is not populated
      IF v_referrer_email IS NULL OR btrim(v_referrer_email) = '' THEN
        SELECT email INTO v_referrer_email FROM auth.users WHERE id = v_referrer;
      END IF;

      -- Send email notification to referrer
      IF v_referrer_email IS NOT NULL AND btrim(v_referrer_email) <> '' THEN
        SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_functions_url';
        SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';
        SELECT value INTO v_notify_secret FROM public._push_trigger_config WHERE key = 'notify_secret';

        IF v_url IS NOT NULL AND v_anon_key IS NOT NULL AND v_notify_secret IS NOT NULL THEN
          v_subject := 'You have a new invite on Instiy! 🎉';
          v_referrer_name := COALESCE(NULLIF(btrim(v_referrer_name), ''), 'there');

          v_html :=
            $html$<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$html$ || v_subject || $html$</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; color: #1c1917; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 20px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 36px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 22px; font-weight: 700; }
    .body { padding: 28px 24px; font-size: 15px; line-height: 1.6; }
    .card { background: #f5f3ff; border: 1.5px dashed #6c47ff; border-radius: 14px; padding: 18px; margin: 20px 0; text-align: center; }
    .code-title { font-size: 11px; text-transform: uppercase; font-weight: 600; letter-spacing: 1px; color: #6c47ff; margin-bottom: 4px; }
    .code-val { font-size: 24px; font-weight: 800; color: #4F2EE8; letter-spacing: 2px; }
    .btn { display: inline-block; background: linear-gradient(135deg, #6c47ff, #8B5CF6); color: white !important; text-decoration: none; padding: 14px 28px; border-radius: 12px; font-weight: 600; font-size: 15px; margin-top: 10px; }
    .footer { padding: 20px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/assets/instiy-logo.png" alt="Instiy" style="height: 42px; margin-bottom: 12px; display: inline-block;" onerror="this.style.display='none'" />
      <h1>New Invite Joined! 🎉</h1>
    </div>
    <div class="body">
      <p>Hi <strong>$html$ || v_referrer_name || $html$</strong>,</p>
      <p>Awesome news! <strong>$html$ || v_invitee_name || $html$</strong> just joined Instiy using your referral code:</p>
      <div class="card">
        <div class="code-title">Referral Code Used</div>
        <div class="code-val">$html$ || v_ref_code || $html$</div>
      </div>
      <p>Once their first qualifying order on Instiy is delivered, you will automatically earn referral reward points!</p>
      <div style="text-align: center; margin-top: 24px;">
        <a href="https://instiy.com/referral" class="btn">View Referral Dashboard</a>
      </div>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>$html$;

          PERFORM net.http_post(
            url := v_url || '/functions/v1/send-email',
            headers := jsonb_build_object(
              'Content-Type', 'application/json',
              'Authorization', 'Bearer ' || v_anon_key,
              'x-notify-secret', v_notify_secret
            ),
            body := jsonb_build_object(
              'to', btrim(v_referrer_email),
              'subject', v_subject,
              'html', v_html
            )
          );
        END IF;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- C. Trigger to notify user via email anytime referral points are awarded
CREATE OR REPLACE FUNCTION public.notify_referral_points_awarded()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_diff INT;
  v_url TEXT;
  v_anon_key TEXT;
  v_notify_secret TEXT;
  v_subject TEXT;
  v_html TEXT;
  v_name TEXT;
  v_email TEXT;
BEGIN
  v_diff := NEW.referral_points - OLD.referral_points;
  IF v_diff <= 0 THEN
    RETURN NEW;
  END IF;

  v_email := NEW.email;
  IF v_email IS NULL OR btrim(v_email) = '' THEN
    SELECT email INTO v_email FROM auth.users WHERE id = NEW.id;
  END IF;

  IF v_email IS NULL OR btrim(v_email) = '' THEN
    RETURN NEW;
  END IF;

  v_name := COALESCE(NULLIF(btrim(NEW.full_name), ''), 'there');

  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_functions_url';
  SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';
  SELECT value INTO v_notify_secret FROM public._push_trigger_config WHERE key = 'notify_secret';

  IF v_url IS NOT NULL AND v_anon_key IS NOT NULL AND v_notify_secret IS NOT NULL THEN
    v_subject := 'You earned ' || v_diff || ' referral points on Instiy! 🎁';

    v_html :=
      $html$<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$html$ || v_subject || $html$</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; color: #1c1917; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 20px; overflow: hidden; box-shadow: 0 4px 20px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #10B981, #059669); padding: 36px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 22px; font-weight: 700; }
    .body { padding: 28px 24px; font-size: 15px; line-height: 1.6; }
    .points-card { background: #ECFDF5; border: 2px solid #10B981; border-radius: 14px; padding: 20px; margin: 20px 0; text-align: center; }
    .points-label { font-size: 12px; text-transform: uppercase; font-weight: 600; letter-spacing: 1px; color: #059669; margin-bottom: 4px; }
    .points-val { font-size: 32px; font-weight: 800; color: #047857; }
    .btn { display: inline-block; background: linear-gradient(135deg, #10B981, #059669); color: white !important; text-decoration: none; padding: 14px 28px; border-radius: 12px; font-weight: 600; font-size: 15px; margin-top: 10px; }
    .footer { padding: 20px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/assets/instiy-logo.png" alt="Instiy" style="height: 42px; margin-bottom: 12px; display: inline-block;" onerror="this.style.display='none'" />
      <h1>Points Awarded! 🎁</h1>
    </div>
    <div class="body">
      <p>Hi <strong>$html$ || v_name || $html$</strong>,</p>
      <p>Great news! You have just been awarded referral points in your Instiy account:</p>
      <div class="points-card">
        <div class="points-label">Points Added</div>
        <div class="points-val">+$html$ || v_diff || $html$ Points</div>
      </div>
      <p>Your referral points balance has been credited. You can check your rewards and balance anytime in your wallet.</p>
      <div style="text-align: center; margin-top: 24px;">
        <a href="https://instiy.com/wallet" class="btn">View My Wallet</a>
      </div>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>$html$;

    PERFORM net.http_post(
      url := v_url || '/functions/v1/send-email',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_anon_key,
        'x-notify-secret', v_notify_secret
      ),
      body := jsonb_build_object(
        'to', btrim(v_email),
        'subject', v_subject,
        'html', v_html
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_notify_referral_points ON public.users;
CREATE TRIGGER trigger_notify_referral_points
  AFTER UPDATE OF referral_points ON public.users
  FOR EACH ROW
  WHEN (OLD.referral_points IS DISTINCT FROM NEW.referral_points AND NEW.referral_points > OLD.referral_points)
  EXECUTE FUNCTION public.notify_referral_points_awarded();
