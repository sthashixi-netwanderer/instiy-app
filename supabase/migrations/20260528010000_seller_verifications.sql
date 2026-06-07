-- Seller verification requests table
-- Stores multi-step verification submissions for seller profile badges

CREATE TABLE IF NOT EXISTS public.seller_verifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  -- Student info
  date_of_birth DATE NOT NULL,
  year_of_entrance INTEGER NOT NULL,
  graduation_year INTEGER NOT NULL,
  residential_address TEXT NOT NULL,
  digital_address TEXT,

  -- Media files (R2 URLs)
  student_id_front_url TEXT NOT NULL,
  student_id_back_url TEXT NOT NULL,
  live_video_url TEXT NOT NULL,

  -- Status: pending | approved | rejected | cancelled | revoked
  status TEXT NOT NULL DEFAULT 'pending',
  admin_notes TEXT,
  reviewed_by UUID REFERENCES auth.users(id),
  reviewed_at TIMESTAMPTZ,

  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Unique index: only one active (pending) verification per user
CREATE UNIQUE INDEX idx_seller_verifications_pending
  ON public.seller_verifications (user_id)
  WHERE status = 'pending';

-- Index for admin queries
CREATE INDEX idx_seller_verifications_status
  ON public.seller_verifications (status, created_at DESC);

-- RLS policies
ALTER TABLE public.seller_verifications ENABLE ROW LEVEL SECURITY;

-- Users can read their own verification records
CREATE POLICY "Users can view own verifications"
  ON public.seller_verifications
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own verification request
CREATE POLICY "Users can create own verification"
  ON public.seller_verifications
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own (for cancelling)
CREATE POLICY "Users can update own verifications"
  ON public.seller_verifications
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Admins can read all verifications
CREATE POLICY "Admins can view all verifications"
  ON public.seller_verifications
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.is_admin = true
    )
  );

-- Admins can update all verifications (approve/reject/revoke)
CREATE POLICY "Admins can update all verifications"
  ON public.seller_verifications
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid() AND users.is_admin = true
    )
  );

-- Function to approve verification (sets user is_verified = true)
CREATE OR REPLACE FUNCTION public.approve_seller_verification(
  p_verification_id UUID,
  p_admin_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_verification RECORD;
BEGIN
  -- Get the verification
  SELECT * INTO v_verification
  FROM public.seller_verifications
  WHERE id = p_verification_id AND status = 'pending';

  IF v_verification IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Verification not found or not pending');
  END IF;

  -- Update verification status
  UPDATE public.seller_verifications
  SET status = 'approved',
      admin_notes = p_notes,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_verification_id;

  -- Set user as verified
  UPDATE public.users
  SET is_verified = true, updated_at = now()
  WHERE id = v_verification.user_id;

  RETURN jsonb_build_object('success', true, 'user_id', v_verification.user_id);
END;
$$;

-- Function to reject verification
CREATE OR REPLACE FUNCTION public.reject_seller_verification(
  p_verification_id UUID,
  p_admin_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_verification RECORD;
BEGIN
  SELECT * INTO v_verification
  FROM public.seller_verifications
  WHERE id = p_verification_id AND status = 'pending';

  IF v_verification IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Verification not found or not pending');
  END IF;

  UPDATE public.seller_verifications
  SET status = 'rejected',
      admin_notes = p_notes,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_verification_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- Function to revoke verification (sets user is_verified = false)
CREATE OR REPLACE FUNCTION public.revoke_seller_verification(
  p_verification_id UUID,
  p_admin_id UUID,
  p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_verification RECORD;
BEGIN
  SELECT * INTO v_verification
  FROM public.seller_verifications
  WHERE id = p_verification_id AND status = 'approved';

  IF v_verification IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Verification not found or not approved');
  END IF;

  UPDATE public.seller_verifications
  SET status = 'revoked',
      admin_notes = p_notes,
      reviewed_by = p_admin_id,
      reviewed_at = now(),
      updated_at = now()
  WHERE id = p_verification_id;

  -- Remove verified badge from user
  UPDATE public.users
  SET is_verified = false, updated_at = now()
  WHERE id = v_verification.user_id;

  RETURN jsonb_build_object('success', true, 'user_id', v_verification.user_id);
END;
$$;

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION public.handle_seller_verification_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER seller_verifications_updated_at
  BEFORE UPDATE ON public.seller_verifications
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_seller_verification_updated_at();
