-- Fix condition CHECK constraint to match Dart enum values.
-- The app sends 'brandNew', 'used', 'refurbished' but the DB only allowed
-- 'new_', 'likeNew', 'good', 'fair', 'poor'.

-- Step 1: Drop the old constraint FIRST so we can update data freely
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_condition_check;

-- Step 2: Migrate any existing rows that use old condition values
UPDATE public.products SET condition = 'brandNew'    WHERE condition = 'new_';
UPDATE public.products SET condition = 'used'        WHERE condition IN ('good', 'fair', 'poor');
UPDATE public.products SET condition = 'refurbished' WHERE condition = 'likeNew';

-- Step 3: Add the new constraint matching the Dart enum
ALTER TABLE public.products ADD CONSTRAINT products_condition_check
  CHECK (condition IN ('brandNew', 'used', 'refurbished'));
