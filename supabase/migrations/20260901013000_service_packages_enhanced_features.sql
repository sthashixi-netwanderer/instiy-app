-- Add delivery_duration, delivery_unit, and features to service_packages
ALTER TABLE public.service_packages
  ADD COLUMN IF NOT EXISTS delivery_duration INT DEFAULT 3,
  ADD COLUMN IF NOT EXISTS delivery_unit TEXT DEFAULT 'days',
  ADD COLUMN IF NOT EXISTS features JSONB DEFAULT '[]'::jsonb;

-- Relax check constraint on delivery_days so zero/custom values for minute/hour packages don't fail
ALTER TABLE public.service_packages
  DROP CONSTRAINT IF EXISTS service_packages_delivery_days_check;

ALTER TABLE public.service_packages
  ADD CONSTRAINT service_packages_delivery_days_check
  CHECK (delivery_days >= 0);

-- Backfill delivery_duration and delivery_unit
UPDATE public.service_packages
SET delivery_duration = COALESCE(delivery_days, 3),
    delivery_unit = 'days'
WHERE delivery_duration IS NULL OR delivery_unit IS NULL;
