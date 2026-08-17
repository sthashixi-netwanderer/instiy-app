-- Add wallet_tag column to users table
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS wallet_tag TEXT UNIQUE;

-- Update existing users with unique wallet tags
DO $$
DECLARE
  u RECORD;
  base_tag TEXT;
  final_tag TEXT;
  counter INT;
  tag_exists BOOLEAN;
BEGIN
  FOR u IN SELECT id, full_name, email FROM public.users WHERE wallet_tag IS NULL LOOP
    base_tag := COALESCE(u.full_name, u.email);
    base_tag := lower(regexp_replace(base_tag, '[^a-zA-Z]', '', 'g'));
    IF length(base_tag) < 5 THEN
      base_tag := rpad(base_tag, 5, 'x');
    END IF;
    
    final_tag := base_tag;
    counter := 1;
    LOOP
      SELECT EXISTS(SELECT 1 FROM public.users WHERE wallet_tag = final_tag) INTO tag_exists;
      IF NOT tag_exists THEN
        EXIT;
      END IF;
      final_tag := base_tag || counter::TEXT;
      counter := counter + 1;
    END LOOP;
    
    UPDATE public.users SET wallet_tag = final_tag WHERE id = u.id;
  END LOOP;
END;
$$;

-- Make wallet_tag NOT NULL now that existing rows are populated
ALTER TABLE public.users ALTER COLUMN wallet_tag SET NOT NULL;

-- Update handle_new_user trigger function to generate unique wallet tags
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  base_tag TEXT;
  final_tag TEXT;
  counter INT := 1;
  tag_exists BOOLEAN;
BEGIN
  -- Derive base tag from full name or email
  base_tag := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email);
  -- Clean it to only contain lowercase letters
  base_tag := lower(regexp_replace(base_tag, '[^a-zA-Z]', '', 'g'));
  -- Ensure at least 5 letters
  IF length(base_tag) < 5 THEN
    base_tag := rpad(base_tag, 5, 'x');
  END IF;
  
  final_tag := base_tag;
  
  -- Loop to ensure uniqueness
  LOOP
    SELECT EXISTS(SELECT 1 FROM public.users WHERE wallet_tag = final_tag) INTO tag_exists;
    IF NOT tag_exists THEN
      EXIT;
    END IF;
    final_tag := base_tag || counter::TEXT;
    counter := counter + 1;
  END LOOP;

  INSERT INTO public.users (id, email, full_name, university, phone_number, wallet_tag)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.raw_user_meta_data->>'university',
    NEW.raw_user_meta_data->>'phone_number',
    final_tag
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
