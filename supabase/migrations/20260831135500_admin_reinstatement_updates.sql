-- Update get_admin_reports to use LEFT JOIN for reported user
CREATE OR REPLACE FUNCTION public.get_admin_reports()
RETURNS TABLE(
  report_id uuid,
  reporter_id uuid,
  reporter_name text,
  reporter_avatar text,
  reporter_university text,
  reported_user_id uuid,
  reported_name text,
  reported_avatar text,
  reported_university text,
  reported_suspended boolean,
  category text,
  description text,
  evidence_urls text[],
  conversation_id uuid,
  product_id uuid,
  product_title text,
  product_image text,
  product_price numeric,
  service_id uuid,
  service_title text,
  service_image text,
  service_price numeric,
  service_status text,
  status text,
  admin_notes text,
  is_read boolean,
  complaint_id uuid,
  complaint_text text,
  complaint_status text,
  created_at timestamp with time zone,
  updated_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

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
    r.media_urls AS evidence_urls,
    r.conversation_id,
    r.product_id,
    p.title AS product_title,
    CASE
      WHEN p.image_urls IS NOT NULL AND array_length(p.image_urls, 1) > 0 THEN p.image_urls[1]
      ELSE NULL
    END AS product_image,
    p.price AS product_price,
    r.service_id,
    s.title AS service_title,
    CASE
      WHEN s.image_urls IS NOT NULL AND array_length(s.image_urls, 1) > 0 THEN s.image_urls[1]
      ELSE NULL
    END AS service_image,
    s.price AS service_price,
    s.status AS service_status,
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
  LEFT JOIN public.users rup ON rup.id = r.reported_user_id
  LEFT JOIN public.products p ON p.id = r.product_id
  LEFT JOIN public.services s ON s.id = r.service_id
  LEFT JOIN public.user_complaints uc ON uc.report_id = r.id
  ORDER BY r.created_at DESC;
END;
$function$;

-- Update admin_set_service_provider to auto-resolve open appeals and insert in-app notification on reinstatement
CREATE OR REPLACE FUNCTION public.admin_set_service_provider(
  p_user_id uuid,
  p_is_service_provider boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Only administrators can change service provider status';
  END IF;

  UPDATE public.users
  SET is_service_provider = p_is_service_provider,
      updated_at = now()
  WHERE id = p_user_id;

  -- If disabled, deactivate all their services immediately
  IF NOT p_is_service_provider THEN
    UPDATE public.services
    SET status = 'inactive',
        updated_at = now()
    WHERE provider_id = p_user_id
      AND status != 'inactive';
  ELSE
    -- Reinstated: resolve open appeals and send in-app notification
    UPDATE public.reports
    SET status = 'resolved',
        updated_at = now()
    WHERE reporter_id = p_user_id
      AND category = 'service_provider_appeal'
      AND status = 'pending';

    UPDATE public.user_complaints
    SET status = 'resolved',
        updated_at = now()
    WHERE user_id = p_user_id
      AND status IN ('pending', 'reviewed')
      AND (
        report_id IN (
          SELECT id FROM public.reports WHERE category = 'service_provider_appeal'
        )
        OR report_id IS NULL
      );

    INSERT INTO public.notifications (user_id, title, body, type)
    VALUES (
      p_user_id,
      'Service Provider Account Reinstated',
      'Your service provider account has been reinstated by an administrator. You can now manage and publish your services on Instiy.',
      'system'
    );
  END IF;
END;
$$;
