-- ============================================================
-- Fix: Recreate get_admin_reports with new return type
-- The previous migration recorded in schema_migrations but
-- failed at the CREATE OR REPLACE because Postgres cannot
-- change a function's return type with CREATE OR REPLACE.
-- ============================================================

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

-- Ensure get_unread_report_count exists (may have been skipped)
CREATE OR REPLACE FUNCTION get_unread_report_count()
RETURNS INTEGER AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.reports
  WHERE is_read = FALSE;
$$ LANGUAGE sql SECURITY DEFINER;

-- Ensure mark_report_read exists (may have been skipped)
CREATE OR REPLACE FUNCTION mark_report_read(report_uuid UUID)
RETURNS VOID AS $$
  UPDATE public.reports SET is_read = TRUE WHERE id = report_uuid;
$$ LANGUAGE sql SECURITY DEFINER;
