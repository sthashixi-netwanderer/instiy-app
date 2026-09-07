-- ============================================================
-- Referral program: referee rewards are now fully automatic
-- ============================================================
-- The referred user's half-share is credited at qualification
-- time (same signal as the referrer share). No admin approval.
-- Removes the award_referee_points RPC and the pending queue.

-- 1. Award: credit BOTH shares at qualification ------------------
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
  v_referee INT;
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

  -- Integer division floors the referee half-share.
  v_referee := v_points / 2;

  -- Status recheck keeps this idempotent under races.
  UPDATE public.referrals
  SET status = 'qualified',
      qualified_order_id = NEW.id,
      qualified_at = NOW(),
      points_awarded = v_points,
      referee_points = v_referee,
      referee_awarded_at = NOW()
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

  -- Referee share: automatic, credited immediately.
  IF v_referee > 0 THEN
    UPDATE public.users
    SET referral_points = referral_points + v_referee
    WHERE id = v_referral.referred_id;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_referral.referred_id,
      'Referral reward earned',
      'You earned ' || v_referee
        || ' referral points for joining through a referral!',
      'referral',
      jsonb_build_object(
        'type', 'referee_award',
        'points', v_referee,
        'referral_id', v_referral.id,
        'order_id', NEW.id
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

-- 2. Reversal: always take back both shares on full refund -------
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

  IF v_referral.referee_points > 0 THEN
    UPDATE public.users
    SET referral_points = GREATEST(
      referral_points - v_referral.referee_points, 0
    )
    WHERE id = v_referral.referred_id;

    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_referral.referred_id,
      'Referral reward reversed',
      'The qualifying order was refunded — '
        || v_referral.referee_points
        || ' referral points were removed.',
      'referral',
      jsonb_build_object(
        'type', 'referral_reversal',
        'points', v_referral.referee_points,
        'referral_id', v_referral.id,
        'order_id', v_order_id
      )
    );
  END IF;

  UPDATE public.referrals
  SET status = 'registered',
      qualified_order_id = NULL,
      qualified_at = NULL,
      points_awarded = 0,
      referee_points = 0,
      referee_awarded_at = NULL
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

-- 3. Backfill: release any shares still awaiting approval --------
UPDATE public.users u
SET referral_points = u.referral_points + r.referee_points
FROM public.referrals r
WHERE r.status = 'qualified'
  AND r.referee_awarded_at IS NULL
  AND r.referee_points > 0
  AND u.id = r.referred_id;

INSERT INTO public.notifications (user_id, title, body, type, data)
SELECT
  r.referred_id,
  'Referral reward earned',
  'You earned ' || r.referee_points
    || ' referral points for joining through a referral!',
  'referral',
  jsonb_build_object(
    'type', 'referee_award',
    'points', r.referee_points,
    'referral_id', r.id
  )
FROM public.referrals r
WHERE r.status = 'qualified'
  AND r.referee_awarded_at IS NULL
  AND r.referee_points > 0;

UPDATE public.referrals
SET referee_awarded_at = NOW()
WHERE status = 'qualified'
  AND referee_awarded_at IS NULL
  AND referee_points > 0;

COMMENT ON COLUMN public.referrals.referee_awarded_at IS
  'When the referee share was credited (automatically at qualification).';

-- 4. Remove the manual approval path -----------------------------
DROP FUNCTION IF EXISTS public.award_referee_points(UUID);
DROP INDEX IF EXISTS public.idx_referrals_pending_referee;
