CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  base_tag TEXT;
  final_tag TEXT;
  counter INT := 1;
  tag_exists BOOLEAN;
BEGIN
  -- Prefer user's custom wallet tag if provided and valid (at least 5 characters)
  base_tag := NEW.raw_user_meta_data->>'wallet_tag';
  
  IF base_tag IS NULL OR length(base_tag) < 5 THEN
    -- Fallback to generating from full_name or email
    base_tag := COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email);
    base_tag := lower(regexp_replace(base_tag, '[^a-zA-Z]', '', 'g'));
    IF length(base_tag) < 5 THEN
      base_tag := rpad(base_tag, 5, 'x');
    END IF;
  ELSE
    base_tag := lower(regexp_replace(base_tag, '[^a-zA-Z0-9]', '', 'g'));
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
