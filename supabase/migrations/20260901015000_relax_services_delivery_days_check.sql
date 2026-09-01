-- Relax check constraint on services.delivery_days so minute/hour packages (where delivery_days = 0) don't violate constraint
ALTER TABLE public.services
  DROP CONSTRAINT IF EXISTS services_delivery_days_check;

ALTER TABLE public.services
  ADD CONSTRAINT services_delivery_days_check
  CHECK (delivery_days IS NULL OR delivery_days >= 0);
