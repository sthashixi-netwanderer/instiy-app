-- Add location_url column to business_profiles for Google Maps location
ALTER TABLE public.business_profiles
ADD COLUMN IF NOT EXISTS location_url TEXT;
