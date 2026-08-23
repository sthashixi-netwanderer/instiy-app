-- Finish freezing users.is_seller.
--
-- The column-level REVOKEs in 20260823100000 are no-ops while a table-level
-- UPDATE/INSERT grant exists (PostgreSQL ACLs are additive-only), so narrow
-- the grants instead: authenticated keeps every column EXCEPT is_seller,
-- which only the SECURITY DEFINER become_seller() RPC / service role / owner
-- can write.
--
-- NOTE: any future user-writable column added to public.users must be added
-- to these column lists — and is_seller never is.

REVOKE UPDATE ON TABLE public.users FROM authenticated;
GRANT UPDATE (id, email, full_name, avatar_url, university, bio, phone_number,
              created_at, updated_at, is_verified, is_admin, wallet_tag,
              last_seen, suspended, suspended_at, suspended_report_id)
  ON TABLE public.users TO authenticated;

REVOKE INSERT ON TABLE public.users FROM authenticated;
GRANT INSERT (id, email, full_name, avatar_url, university, bio, phone_number,
              created_at, updated_at, is_verified, is_admin, wallet_tag,
              last_seen, suspended, suspended_at, suspended_report_id)
  ON TABLE public.users TO authenticated;
