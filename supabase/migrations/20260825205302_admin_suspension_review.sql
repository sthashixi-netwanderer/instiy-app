-- Admin tooling for reviewing suspended-user complaints and reinstating accounts.
--
-- 1. get_suspended_complaints(): feed for the admin Reports "Suspended" tab —
--    every complaint filed by a currently-suspended user, joined with the
--    user's account details and the report that triggered the suspension.
-- 2. admin_unsuspend_user(): one-shot reinstatement — lifts the suspension,
--    resolves the user's open complaints, and inserts a reinstatement
--    notification (the app's realtime watcher bounces the user back in).
-- 3. get_admin_reports(): hardened with an is_admin() guard (it exposes user
--    data and was previously callable by any authenticated user).

create or replace function public.get_suspended_complaints()
returns table (
  complaint_id uuid,
  complaint_text text,
  complaint_status text,
  complaint_admin_notes text,
  complaint_created_at timestamptz,
  user_id uuid,
  user_name text,
  user_email text,
  user_avatar text,
  user_university text,
  user_joined_at timestamptz,
  user_is_seller boolean,
  user_is_verified boolean,
  suspended_at timestamptz,
  reports_against_count bigint,
  report_id uuid,
  report_category text,
  report_description text,
  report_status text,
  reporter_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access required';
  end if;

  return query
  select
    uc.id,
    uc.complaint_text,
    uc.status,
    uc.admin_notes,
    uc.created_at,
    u.id,
    u.full_name,
    u.email,
    u.avatar_url,
    u.university,
    u.created_at,
    u.is_seller,
    u.is_verified,
    u.suspended_at,
    (select count(*) from public.reports r2 where r2.reported_user_id = u.id) as reports_against_count,
    r.id,
    r.category,
    r.description,
    r.status,
    rp.full_name
  from public.user_complaints uc
  join public.users u on u.id = uc.user_id
  left join public.reports r on r.id = uc.report_id
  left join public.users rp on rp.id = r.reporter_id
  where u.suspended = true
  order by uc.created_at desc;
end;
$$;

create or replace function public.admin_unsuspend_user(p_user_id uuid, p_admin_notes text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access required';
  end if;

  update public.users
     set suspended = false,
         suspended_at = null,
         suspended_report_id = null,
         updated_at = now()
   where id = p_user_id;

  -- The appeal was accepted: resolve any open complaints from this user.
  update public.user_complaints
     set status = 'resolved',
         admin_notes = coalesce(nullif(btrim(p_admin_notes), ''), admin_notes),
         updated_at = now()
   where user_id = p_user_id
     and status in ('pending', 'reviewed');

  insert into public.notifications (user_id, title, body, type)
  values (
    p_user_id,
    'Account Reinstated',
    'Your account has been reviewed and reinstated. You can use Instiy again.',
    'system'
  );
end;
$$;

revoke execute on function public.get_suspended_complaints() from public, anon;
revoke execute on function public.admin_unsuspend_user(uuid, text) from public, anon;
grant execute on function public.get_suspended_complaints() to authenticated;
grant execute on function public.admin_unsuspend_user(uuid, text) to authenticated;

create or replace function public.get_admin_reports()
returns table(report_id uuid, reporter_id uuid, reporter_name text, reporter_avatar text, reporter_university text, reported_user_id uuid, reported_name text, reported_avatar text, reported_university text, reported_suspended boolean, category text, description text, conversation_id uuid, product_id uuid, product_title text, product_image text, product_price numeric, status text, admin_notes text, is_read boolean, complaint_id uuid, complaint_text text, complaint_status text, created_at timestamp with time zone, updated_at timestamp with time zone)
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access required';
  end if;

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
$function$;

revoke execute on function public.get_admin_reports() from public, anon;
grant execute on function public.get_admin_reports() to authenticated;
