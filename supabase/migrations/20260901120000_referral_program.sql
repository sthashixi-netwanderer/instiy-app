-- ============================================================
-- Referral program
-- ============================================================
-- Users share a referral code/link. Registration through a code
-- records a `referrals` row (status 'registered'). When the
-- referred user's order is fully delivered and its delivered value
-- meets the admin-configured minimum, the referrer is awarded
-- points (users.referral_points). A full order refund reverses the
-- award. Config lives in platform_settings key 'referral_program':
--   {"enabled": true, "min_purchase_amount_ghs": 50,
--    "points_per_referral": 500}

-- 1. User columns ------------------------------------------------
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS referral_code TEXT UNIQUE,
  ADD COLUMN IF NOT EXISTS referral_points INT NOT NULL DEFAULT 0;

-- Backfill unique 8-char codes for existing users (unambiguous
-- alphabet: no 0/O/1/I).
DO $$
DECLARE
  u RECORD;
  v_code TEXT;
  v_exists BOOLEAN;
  v_alphabet TEXT := '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
BEGIN
  FOR u IN SELECT id FROM public.users WHERE referral_code IS NULL LOOP
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
      ) INTO v_exists;
      EXIT WHEN NOT v_exists;
    END LOOP;
    UPDATE public.users SET referral_code = v_code WHERE id = u.id;
  END LOOP;
END;
$$;

-- 2. Referrals table ---------------------------------------------
CREATE TABLE IF NOT EXISTS public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  referred_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  code_used TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'registered'
    CHECK (status IN ('registered', 'qualified')),
  qualified_order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  points_awarded INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  qualified_at TIMESTAMPTZ,
  -- A user can only ever be referred once.
  UNIQUE (referred_id)
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer_id
  ON public.referrals (referrer_id);
CREATE INDEX IF NOT EXISTS idx_referrals_referred_id
  ON public.referrals (referred_id);

COMMENT ON TABLE public.referrals IS
  'One row per referred signup; the referral qualifies (and the referrer is '
  'awarded points) when the referred user''s order is delivered and meets the '
  'admin-configured minimum purchase amount.';

-- 3. Admin-configurable settings ---------------------------------
INSERT INTO public.platform_settings (key, value)
VALUES (
  'referral_program',
  '{"enabled": true, "min_purchase_amount_ghs": 50, "points_per_referral": 500}'::jsonb
)
ON CONFLICT (key) DO NOTHING;

-- 4. Signup: own code + record incoming referral ------------------
-- Extends handle_new_user (latest def: custom wallet tags) with
-- referral code generation and the referrals insert. The code rides
-- Supabase auth.signUp(data: {'referral_code': ...}) into
-- raw_user_meta_data; invalid codes are ignored silently.
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
BEGIN
  -- Prefer user's custom wallet tag if provided and valid (at least 5 characters)
  base_tag := NEW.raw_user_meta_data->>'wallet_tag';

  IF base_tag IS NULL OR length(base_tag) < 5 THEN
    -- Fallback to generating from full_name or email
    base_tag := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email);
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
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.raw_user_meta_data->>'university',
    NEW.raw_user_meta_data->>'phone_number',
    final_tag,
    v_code
  );

  -- Record the referral if a valid code was supplied at signup.
  v_ref_code := upper(trim(COALESCE(NEW.raw_user_meta_data->>'referral_code', '')));
  IF v_ref_code ~ '^[A-Z0-9]{4,32}$' THEN
    SELECT id INTO v_referrer
    FROM public.users
    WHERE referral_code = v_ref_code
      AND id <> NEW.id;
    IF v_referrer IS NOT NULL THEN
      INSERT INTO public.referrals (referrer_id, referred_id, code_used, status)
      VALUES (v_referrer, NEW.id, v_ref_code, 'registered');
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Award points when the referred user's order is delivered -----
-- The delivery RPCs (verify_delivery / complete_seller_order_item /
-- verify_delivery_by_code) set orders.status='delivered' once every
-- item is delivered or cancelled, so this single transition is the
-- "purchase completed" signal.
CREATE OR REPLACE FUNCTION public.process_referral_award()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_referral RECORD;
  v_cfg JSONB;
  v_enabled BOOLEAN;
  v_min_amount NUMERIC;
  v_points INT;
  v_delivered_total NUMERIC;
  v_qualifying_amount NUMERIC;
  v_referrer UUID;
BEGIN
  -- Only the buyer's first still-pending referral can qualify.
  SELECT * INTO v_referral
  FROM public.referrals
  WHERE referred_id = NEW.buyer_id
    AND status = 'registered'
  FOR UPDATE;

  IF v_referral.id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT value INTO v_cfg
  FROM public.platform_settings
  WHERE key = 'referral_program';

  v_enabled := COALESCE((v_cfg->>'enabled')::boolean, true);
  v_min_amount := COALESCE((v_cfg->>'min_purchase_amount_ghs')::numeric, 0);
  v_points := COALESCE((v_cfg->>'points_per_referral')::int, 0);

  IF NOT v_enabled OR v_points <= 0 THEN
    RETURN NEW;
  END IF;

  -- Delivered value of this order: items that actually delivered
  -- (cancelled items excluded) plus the order's delivery fee.
  SELECT COALESCE(SUM(oi.price * oi.quantity), 0)
  INTO v_delivered_total
  FROM public.order_items oi
  WHERE oi.order_id = NEW.id
    AND oi.status = 'delivered';

  v_qualifying_amount := v_delivered_total + COALESCE(NEW.delivery_fee, 0);

  IF v_qualifying_amount < v_min_amount THEN
    RETURN NEW;
  END IF;

  -- Status recheck keeps this idempotent under races.
  UPDATE public.referrals
  SET status = 'qualified',
      qualified_order_id = NEW.id,
      qualified_at = NOW(),
      points_awarded = v_points
  WHERE id = v_referral.id
    AND status = 'registered'
  RETURNING referrer_id INTO v_referrer;

  IF v_referrer IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.users
  SET referral_points = referral_points + v_points
  WHERE id = v_referrer;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_referrer,
    'Referral reward earned',
    'Your referral''s order was delivered — you earned '
      || v_points || ' referral points!',
    'referral',
    jsonb_build_object(
      'type', 'referral_award',
      'points', v_points,
      'referral_id', v_referral.id,
      'order_id', NEW.id
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_referral_award ON public.orders;
CREATE TRIGGER trigger_referral_award
  AFTER UPDATE ON public.orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM 'delivered' AND NEW.status = 'delivered')
  EXECUTE FUNCTION public.process_referral_award();

-- 6. Reverse the award on a full order refund ---------------------
-- cancel_order refunds via credit_wallet which inserts a
-- wallet_transactions row with reference 'REFUND-<order_uuid>'.
-- (Item-level refunds use an 'ITEM-REFUND-...' reference and do not
-- match.) SECURITY DEFINER is required to see past referrals RLS.
CREATE OR REPLACE FUNCTION public.process_referral_reversal()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order_id UUID;
  v_referral RECORD;
BEGIN
  IF NEW.type <> 'deposit' OR NEW.reference IS NULL
     OR NEW.reference NOT LIKE 'REFUND-%' THEN
    RETURN NEW;
  END IF;

  -- 'REFUND-' is 7 chars; guard against non-uuid payloads.
  BEGIN
    v_order_id := substring(NEW.reference FROM 8)::uuid;
  EXCEPTION WHEN invalid_text_representation THEN
    RETURN NEW;
  END;

  SELECT * INTO v_referral
  FROM public.referrals
  WHERE qualified_order_id = v_order_id
    AND status = 'qualified'
  FOR UPDATE;

  IF v_referral.id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE public.users
  SET referral_points = GREATEST(referral_points - v_referral.points_awarded, 0)
  WHERE id = v_referral.referrer_id;

  UPDATE public.referrals
  SET status = 'registered',
      qualified_order_id = NULL,
      qualified_at = NULL,
      points_awarded = 0
  WHERE id = v_referral.id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_referral.referrer_id,
    'Referral reward reversed',
    'The qualifying order was refunded — '
      || v_referral.points_awarded
      || ' referral points were removed. A new qualifying order will '
      || 're-earn them.',
    'referral',
    jsonb_build_object(
      'type', 'referral_reversal',
      'points', v_referral.points_awarded,
      'referral_id', v_referral.id,
      'order_id', v_order_id
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_referral_reversal ON public.wallet_transactions;
CREATE TRIGGER trigger_referral_reversal
  AFTER INSERT ON public.wallet_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.process_referral_reversal();

-- 7. RLS ----------------------------------------------------------
ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own referrals" ON public.referrals;
CREATE POLICY "Users can view own referrals"
  ON public.referrals FOR SELECT
  TO authenticated
  USING (referrer_id = auth.uid());

DROP POLICY IF EXISTS "Admins manage referrals" ON public.referrals;
CREATE POLICY "Admins manage referrals"
  ON public.referrals FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- 8. Pre-auth code validation RPC --------------------------------
-- The register screen checks codes before signup; users SELECT is
-- authenticated-only so this SECURITY DEFINER helper is the gate.
CREATE OR REPLACE FUNCTION public.check_referral_code(p_code TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_code TEXT := upper(trim(COALESCE(p_code, '')));
BEGIN
  IF v_code = '' THEN
    RETURN FALSE;
  END IF;
  RETURN EXISTS (
    SELECT 1 FROM public.users WHERE referral_code = v_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_referral_code(TEXT) TO anon, authenticated;
