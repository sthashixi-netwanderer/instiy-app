-- Migration: Create Institutions Table and Policies

CREATE TABLE IF NOT EXISTS public.institutions (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  code TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  logo_url TEXT,
  location TEXT,
  url TEXT,
  region TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable Row Level Security (RLS)
ALTER TABLE public.institutions ENABLE ROW LEVEL SECURITY;

-- 1. Anyone can view institutions (including unauthenticated users for sign-up)
DROP POLICY IF EXISTS "Anyone can view institutions" ON public.institutions;
CREATE POLICY "Anyone can view institutions"
  ON public.institutions FOR SELECT
  USING (true);

-- 2. Only administrators can perform write operations (INSERT, UPDATE, DELETE)
DROP POLICY IF EXISTS "Admins can manage institutions" ON public.institutions;
CREATE POLICY "Admins can manage institutions"
  ON public.institutions FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));
