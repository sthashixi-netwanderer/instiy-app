-- ============================================================
-- User Suspension + Complaints System
-- ============================================================

-- 1. Add suspension columns to users
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS suspended BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMPTZ;

-- 2. Add is_read to reports (track which reports admin has seen)
ALTER TABLE public.reports
  ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT FALSE;

-- 3. User complaints table
CREATE TABLE IF NOT EXISTS public.user_complaints (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  report_id UUID REFERENCES public.reports(id) ON DELETE SET NULL,
  complaint_text TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
  admin_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_complaints_user ON public.user_complaints(user_id);
CREATE INDEX idx_complaints_report ON public.user_complaints(report_id);
CREATE INDEX idx_complaints_status ON public.user_complaints(status);

ALTER TABLE public.user_complaints ENABLE ROW LEVEL SECURITY;

-- Users can view their own complaints
CREATE POLICY "Users can view own complaints"
  ON public.user_complaints FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Users can insert their own complaints
CREATE POLICY "Users can insert own complaints"
  ON public.user_complaints FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Admin full access to complaints
CREATE POLICY "Admins can view all complaints"
  ON public.user_complaints FOR SELECT
  TO authenticated
  USING (public.is_admin(auth.uid()));

CREATE POLICY "Admins can update complaints"
  ON public.user_complaints FOR UPDATE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- Auto-update updated_at on complaints
CREATE TRIGGER set_complaints_updated_at
  BEFORE UPDATE ON public.user_complaints
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 4. Update get_admin_reports RPC to include is_read and complaint info
-- Must drop first because PostgreSQL cannot change return type with CREATE OR REPLACE
DROP FUNCTION IF EXISTS get_admin_reports();
CREATE FUNCTION get_admin_reports()
RETURNS TABLE (
  report_id UUID,
  reporter_id UUID,
  reporter_name TEXT,
  reporter_avatar TEXT,
  reporter_university TEXT,
  reported_user_id UUID,
  reported_name TEXT,
  reported_avatar TEXT,
  reported_university TEXT,
  reported_suspended BOOLEAN,
  category TEXT,
  description TEXT,
  conversation_id UUID,
  product_id UUID,
  product_title TEXT,
  product_image TEXT,
  product_price NUMERIC,
  status TEXT,
  admin_notes TEXT,
  is_read BOOLEAN,
  complaint_id UUID,
  complaint_text TEXT,
  complaint_status TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    r.id AS report_id,
    r.reporter_id,
    rp.full_name AS reporter_name,
    rp.avatar_url AS reporter_avatar,
    rp.university AS reporter_university,
    r.reported_user_id,
    rup.full_name AS reported_name,
    rup.avatar_url AS reported_avatar,
    rup.university AS reported_university,
    COALESCE(rup.suspended, FALSE) AS reported_suspended,
    r.category,
    r.description,
    r.conversation_id,
    r.product_id,
    p.title AS product_title,
    CASE
      WHEN p.image_urls IS NOT NULL AND array_length(p.image_urls, 1) > 0 THEN p.image_urls[1]
      ELSE NULL
    END AS product_image,
    p.price AS product_price,
    r.status,
    r.admin_notes,
    r.is_read,
    uc.id AS complaint_id,
    uc.complaint_text,
    uc.status AS complaint_status,
    r.created_at,
    r.updated_at
  FROM public.reports r
  JOIN public.users rp ON rp.id = r.reporter_id
  JOIN public.users rup ON rup.id = r.reported_user_id
  LEFT JOIN public.products p ON p.id = r.product_id
  LEFT JOIN public.user_complaints uc ON uc.report_id = r.id
  ORDER BY r.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. RPC: Get unread report count for admin sidebar
CREATE OR REPLACE FUNCTION get_unread_report_count()
RETURNS INTEGER AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.reports
  WHERE is_read = FALSE;
$$ LANGUAGE sql SECURITY DEFINER;

-- 6. RPC: Mark a report as read
CREATE OR REPLACE FUNCTION mark_report_read(report_uuid UUID)
RETURNS VOID AS $$
  UPDATE public.reports SET is_read = TRUE WHERE id = report_uuid;
$$ LANGUAGE sql SECURITY DEFINER;
