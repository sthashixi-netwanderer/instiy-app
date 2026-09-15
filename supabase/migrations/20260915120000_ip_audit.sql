-- Migration: IP audit trail + admin blocklist
-- Design: docs/superpowers/specs/2026-09-15-ip-audit-design.md

-- 1. Audit events: one row per app cold start (session) or successful login.
--    Written ONLY by the worker (service role); user_id NULL = anonymous.
CREATE TABLE public.ip_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ip_address INET NOT NULL,
  user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL CHECK (event_type IN ('session', 'login')),
  user_agent TEXT,
  platform TEXT,
  os_version TEXT,
  device_model TEXT,
  app_version TEXT,
  country TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ip_events_ip_created_idx ON public.ip_events (ip_address, created_at DESC);
CREATE INDEX ip_events_user_created_idx ON public.ip_events (user_id, created_at DESC);
CREATE INDEX ip_events_created_idx ON public.ip_events (created_at DESC);

-- 2. Admin-managed blocklist.
CREATE TABLE public.blocked_ips (
  ip_address INET PRIMARY KEY,
  reason TEXT NOT NULL DEFAULT '',
  blocked_by UUID REFERENCES public.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 3. RLS: admin-only reads; no client write path at all (service role writes).
ALTER TABLE public.ip_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.blocked_ips ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view IP events" ON public.ip_events;
CREATE POLICY "Admins can view IP events"
  ON public.ip_events FOR SELECT
  TO authenticated
  USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can view blocked IPs" ON public.blocked_ips;
CREATE POLICY "Admins can view blocked IPs"
  ON public.blocked_ips FOR SELECT
  TO authenticated
  USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can manage blocked IPs" ON public.blocked_ips;
CREATE POLICY "Admins can manage blocked IPs"
  ON public.blocked_ips FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()))
  WITH CHECK (public.is_admin(auth.uid()));

-- 4. Admin RPCs. SECURITY DEFINER + explicit gate: these expose
--    IP-to-account linkage, so unlike get_unread_report_count they must
--    refuse non-admins. REVOKE mirrors the product_views pattern.

CREATE OR REPLACE FUNCTION public.get_ip_audit_summary(
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 25,
  p_search TEXT DEFAULT '',
  p_anonymous_only BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  ip_address INET,
  country TEXT,
  event_count BIGINT,
  login_count BIGINT,
  account_count BIGINT,
  anonymous_event_count BIGINT,
  first_seen TIMESTAMPTZ,
  last_seen TIMESTAMPTZ,
  platforms TEXT[],
  device_models TEXT[],
  user_ids UUID[],
  is_blocked BOOLEAN,
  block_reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  RETURN QUERY
  SELECT
    e.ip_address,
    ((array_agg(e.country) FILTER (WHERE e.country IS NOT NULL)))[1] AS country,
    count(*) AS event_count,
    count(*) FILTER (WHERE e.event_type = 'login') AS login_count,
    count(DISTINCT e.user_id) AS account_count,
    count(*) FILTER (WHERE e.user_id IS NULL) AS anonymous_event_count,
    min(e.created_at) AS first_seen,
    max(e.created_at) AS last_seen,
    array_remove(array_agg(DISTINCT e.platform), NULL) AS platforms,
    array_remove(array_agg(DISTINCT e.device_model), NULL) AS device_models,
    array_remove(array_agg(DISTINCT e.user_id), NULL) AS user_ids,
    (b.ip_address IS NOT NULL) AS is_blocked,
    b.reason AS block_reason
  FROM public.ip_events e
  LEFT JOIN public.blocked_ips b ON b.ip_address = e.ip_address
  WHERE (
    p_search = ''
    OR host(e.ip_address) ILIKE '%' || p_search || '%'
    OR EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = e.user_id
        AND (u.email ILIKE '%' || p_search || '%'
             OR u.full_name ILIKE '%' || p_search || '%')
    )
  )
  AND (
    NOT p_anonymous_only
    OR EXISTS (
      SELECT 1 FROM public.ip_events a
      WHERE a.ip_address = e.ip_address AND a.user_id IS NULL
    )
  )
  GROUP BY e.ip_address, b.ip_address, b.reason
  ORDER BY max(e.created_at) DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.get_ip_audit_summary(INT, INT, TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ip_audit_summary(INT, INT, TEXT, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_ip_audit_count(
  p_search TEXT DEFAULT '',
  p_anonymous_only BOOLEAN DEFAULT FALSE
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NOT public.is_admin(auth.uid()) THEN
    RAISE EXCEPTION 'not_admin';
  END IF;

  RETURN (
    SELECT count(DISTINCT e.ip_address)
    FROM public.ip_events e
    WHERE (
      p_search = ''
      OR host(e.ip_address) ILIKE '%' || p_search || '%'
      OR EXISTS (
        SELECT 1 FROM public.users u
        WHERE u.id = e.user_id
          AND (u.email ILIKE '%' || p_search || '%'
               OR u.full_name ILIKE '%' || p_search || '%')
      )
    )
    AND (
      NOT p_anonymous_only
      OR EXISTS (
        SELECT 1 FROM public.ip_events a
        WHERE a.ip_address = e.ip_address AND a.user_id IS NULL
      )
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_ip_audit_count(TEXT, BOOLEAN) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_ip_audit_count(TEXT, BOOLEAN) TO authenticated;

-- 5. Retention: purge audit events older than 180 days, daily at 03:17 UTC.
CREATE EXTENSION IF NOT EXISTS pg_cron;

SELECT cron.schedule(
  'ip-events-retention',
  '17 3 * * *',
  $$DELETE FROM public.ip_events WHERE created_at < now() - interval '180 days'$$
)
WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ip-events-retention');
