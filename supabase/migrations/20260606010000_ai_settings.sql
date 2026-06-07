-- Enable pgcrypto extension for symmetric encryption/decryption
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Create AI configs table
CREATE TABLE IF NOT EXISTS public.ai_configs (
  key_name TEXT PRIMARY KEY,
  key_value BYTEA NOT NULL, -- Encrypted binary data
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS on ai_configs
ALTER TABLE public.ai_configs ENABLE ROW LEVEL SECURITY;

-- Helper to check if a user is an admin
CREATE OR REPLACE FUNCTION public.is_admin_user(user_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.users
    WHERE id = user_id AND is_admin = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RLS policies: only admin users can access the table directly
CREATE POLICY "Admins can manage ai_configs"
  ON public.ai_configs
  TO authenticated
  USING (public.is_admin_user(auth.uid()))
  WITH CHECK (public.is_admin_user(auth.uid()));

-- Stored procedure to set/encrypt AI keys (Admin only)
CREATE OR REPLACE FUNCTION public.set_ai_key(p_key_name TEXT, p_key_value TEXT)
RETURNS VOID AS $$
BEGIN
  -- Security check: verify if the caller is an admin
  IF NOT public.is_admin_user(auth.uid()) THEN
    RAISE EXCEPTION 'Access denied: User is not an admin';
  END IF;

  -- Insert or update key using pgp_sym_encrypt with a secure database passphrase
  INSERT INTO public.ai_configs (key_name, key_value, updated_at)
  VALUES (
    p_key_name,
    pgp_sym_encrypt(p_key_value, 'instiy_sym_secret_passphrase_2026'),
    NOW()
  )
  ON CONFLICT (key_name) DO UPDATE
  SET
    key_value = pgp_sym_encrypt(p_key_value, 'instiy_sym_secret_passphrase_2026'),
    updated_at = NOW();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Stored procedure to get/decrypt AI keys (Authenticated users)
CREATE OR REPLACE FUNCTION public.get_ai_key(p_key_name TEXT)
RETURNS TEXT AS $$
DECLARE
  v_encrypted_val BYTEA;
  v_decrypted_val TEXT;
BEGIN
  -- Security check: must be authenticated
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Access denied: User is not authenticated';
  END IF;

  SELECT key_value INTO v_encrypted_val
  FROM public.ai_configs
  WHERE key_name = p_key_name;

  IF v_encrypted_val IS NULL THEN
    RETURN NULL;
  END IF;

  -- Decrypt and return key
  BEGIN
    v_decrypted_val := pgp_sym_decrypt(v_encrypted_val, 'instiy_sym_secret_passphrase_2026');
    RETURN v_decrypted_val;
  EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
  END;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
