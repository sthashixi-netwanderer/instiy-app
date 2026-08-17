-- Add qr_code_public column to business_profiles table
ALTER TABLE business_profiles
ADD COLUMN IF NOT EXISTS qr_code_public boolean NOT NULL DEFAULT false;
