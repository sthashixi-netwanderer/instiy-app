-- ============================================================
-- Referral program: referee (referred user) rewards
-- ============================================================
-- The referred user now also earns points: half of what the
-- referrer earned (floored), snapshotted from the same config at
-- qualification time. Both shares unlock off the same
-- purchase-completed signal (delivered order meeting the admin
-- minimum). The referrer share stays automatic; the referee share
-- goes PENDING at qualification and is released only by an admin
-- via the award_referee_points RPC (admin panel button). A full
-- order refund reverses both shares.

-- 1. Referee reward columns -------------------------------------
ALTER TABLE public.referrals
  ADD COLUMN IF NOT EXISTS referee_points INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS referee_awarded_at TIMESTAMPTZ;

COMMENT ON COLUMN public.referrals.referee_points IS
  'Half-share (floored) of points_awarded, credited to the referred user once an admin releases it.';
COMMENT ON COLUMN public.referrals.referee_awarded_at IS
  'When an admin awarded the referee share; NULL means awaiting admin approval.';

-- Fast lane for the admin "awaiting approval" queue.
CREATE INDEX IF NOT EXISTS idx_referrals_pending_referee
  ON public.referrals (qualified_at)
  WHERE status = 'qualified' AND referee_awarded_at IS NULL;

-- 2. Award: snapshot the referee half-share at qualification -----
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

  -- Status recheck keeps this idempotent under races. The referee
  -- half-share (integer division floors) is snapshotted here and
  -- stays pending until an admin releases it.
  UPDATE public.referrals
  SET status = 'qualified',
      qualified_order_id = NEW.id,
      qualified_at = NOW(),
      points_awarded = v_points,
      referee_points = v_points / 2
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

-- 3. Reversal: take back both shares on a full order refund ------
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

  -- Reverse the referee share too, but only if an admin released it.
  -- A still-pending share simply evaporates with the reset below.
  IF v_referral.referee_awarded_at IS NOT NULL
     AND v_referral.referee_points > 0 THEN
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

-- 4. Admin release of the referee share --------------------------
-- Idempotent: returns 0 when there is nothing to award.
CREATE OR REPLACE FUNCTION public.award_referee_points(p_referral_id UUID)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_ref RECORD;
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  SELECT * INTO v_ref
  FROM public.referrals
  WHERE id = p_referral_id
  FOR UPDATE;

  IF v_ref.id IS NULL THEN
    RAISE EXCEPTION 'Referral not found';
  END IF;
  IF v_ref.status <> 'qualified' THEN
    RAISE EXCEPTION 'Referral has not qualified yet';
  END IF;
  IF v_ref.referee_awarded_at IS NOT NULL THEN
    RETURN 0;
  END IF;
  IF v_ref.referee_points <= 0 THEN
    RETURN 0;
  END IF;

  UPDATE public.users
  SET referral_points = referral_points + v_ref.referee_points
  WHERE id = v_ref.referred_id;

  UPDATE public.referrals
  SET referee_awarded_at = NOW()
  WHERE id = v_ref.id;

  INSERT INTO public.notifications (user_id, title, body, type, data)
  VALUES (
    v_ref.referred_id,
    'Referral reward earned',
    'You earned ' || v_ref.referee_points
      || ' referral points for joining through a referral!',
    'referral',
    jsonb_build_object(
      'type', 'referee_award',
      'points', v_ref.referee_points,
      'referral_id', v_ref.id
    )
  );

  RETURN v_ref.referee_points;
END;
$$;

GRANT EXECUTE ON FUNCTION public.award_referee_points(UUID)
  TO authenticated;

-- 5. RLS: referred users can read their own incoming referral ----
DROP POLICY IF EXISTS "Users can view incoming referrals" ON public.referrals;
CREATE POLICY "Users can view incoming referrals"
  ON public.referrals FOR SELECT
  TO authenticated
  USING (referred_id = auth.uid());

-- 6. Backfill: existing qualified rows enter the approval queue ---
UPDATE public.referrals
SET referee_points = points_awarded / 2
WHERE status = 'qualified'
  AND referee_points = 0
  AND points_awarded > 0;
