-- The original status CHECK constraint omitted 'cancelled', which is what
-- cancelPermission writes when a seller declines a pending request — so every
-- decline failed with a check-constraint violation. Allow it alongside
-- 'revoked' (seller withdraws an already-granted permission).

ALTER TABLE public.purchase_permissions
  DROP CONSTRAINT IF EXISTS purchase_permissions_status_check;

ALTER TABLE public.purchase_permissions
  ADD CONSTRAINT purchase_permissions_status_check
  CHECK (status IN ('pending', 'granted', 'used', 'expired', 'revoked', 'cancelled'));
