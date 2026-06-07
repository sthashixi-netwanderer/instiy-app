-- Add is_verified column to users table for seller verification
ALTER TABLE public.users
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN DEFAULT false;
