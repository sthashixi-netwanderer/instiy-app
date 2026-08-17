-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table (extends Supabase auth.users)
CREATE TABLE public.users (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  avatar_url TEXT,
  university TEXT,
  bio TEXT,
  phone_number TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Categories table
CREATE TABLE public.categories (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  icon TEXT,
  color_index INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Products table
CREATE TABLE public.products (
  id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  price DECIMAL(10, 2) NOT NULL,
  category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
  image_urls TEXT[] DEFAULT '{}',
  video_urls TEXT[] DEFAULT '{}',
  thumbnail_url TEXT,
  condition TEXT NOT NULL CHECK (condition IN ('brandNew', 'used', 'refurbished')),
  status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'reserved', 'sold')),
  campus TEXT,
  stock_quantity INTEGER DEFAULT 1 NOT NULL,
  delivery_option TEXT DEFAULT 'pickup' NOT NULL CHECK (delivery_option IN ('pickup', 'delivery', 'both')),
  delivery_fee DECIMAL(10, 2) DEFAULT 0 NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT chk_product_delivery_fee CHECK (
    (delivery_option = 'pickup' AND delivery_fee = 0) OR
    (delivery_option IN ('delivery', 'both'))
  )
);

-- Create indexes for better performance
CREATE INDEX idx_products_seller_id ON public.products(seller_id);
CREATE INDEX idx_products_category_id ON public.products(category_id);
CREATE INDEX idx_products_status ON public.products(status);
CREATE INDEX idx_products_created_at ON public.products(created_at DESC);

-- Full-text search index
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS tsvector_search tsvector;
CREATE INDEX idx_products_search ON public.products USING gin(tsvector_search);

-- Function to update search vector
CREATE OR REPLACE FUNCTION update_search_vector()
RETURNS TRIGGER AS $$
BEGIN
  NEW.tsvector_search := 
    setweight(to_tsvector('english', COALESCE(NEW.title, '')), 'A') ||
    setweight(to_tsvector('english', COALESCE(NEW.description, '')), 'B');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update search vector
CREATE TRIGGER trigger_update_search_vector
  BEFORE INSERT OR UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION update_search_vector();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
CREATE TRIGGER trigger_users_updated_at
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER trigger_products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Row Level Security (RLS)
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;

-- Users policies
CREATE POLICY "Users can view all profiles"
  ON public.users FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE
  TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON public.users FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Categories policies (public read, admin write)
CREATE POLICY "Anyone can view categories"
  ON public.categories FOR SELECT
  TO authenticated
  USING (true);

-- Products policies
CREATE POLICY "Anyone can view available products"
  ON public.products FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can create own products"
  ON public.products FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = seller_id);

CREATE POLICY "Users can update own products"
  ON public.products FOR UPDATE
  TO authenticated
  USING (auth.uid() = seller_id);

CREATE POLICY "Users can delete own products"
  ON public.products FOR DELETE
  TO authenticated
  USING (auth.uid() = seller_id);

-- Insert default categories
INSERT INTO public.categories (name, icon, color_index) VALUES
  ('Electronics', 'smartphone', 0),
  ('Textbooks', 'book', 1),
  ('Furniture', 'armchair', 2),
  ('Clothing', 'shirt', 3),
  ('Sports', 'dumbbell', 4),
  ('Music', 'music', 5),
  ('Gaming', 'gamepad', 6),
  ('Other', 'grid', 7);

-- Function to handle new user creation
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, university)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    NEW.raw_user_meta_data->>'university'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger for new user creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user();

-- Create function to handle new message triggers (determine receiver_id & insert notification)
CREATE OR REPLACE FUNCTION public.handle_new_message()
RETURNS TRIGGER AS $$
DECLARE
  v_receiver_id UUID;
  v_sender_name TEXT;
BEGIN
  -- 1. Find the other participant in the conversation to set as receiver_id
  SELECT CASE 
    WHEN participant1_id = NEW.sender_id THEN participant2_id 
    ELSE participant1_id 
  END INTO v_receiver_id
  FROM public.conversations 
  WHERE id = NEW.conversation_id;

  NEW.receiver_id := v_receiver_id;

  -- 2. Fetch the sender's full name for notification title
  SELECT full_name INTO v_sender_name 
  FROM public.users 
  WHERE id = NEW.sender_id;

  -- 3. Automatically insert a notification record for the receiver
  IF v_receiver_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, title, body, type, data)
    VALUES (
      v_receiver_id,
      COALESCE(v_sender_name, 'New Message'),
      NEW.content,
      'message',
      jsonb_build_object('conversation_id', NEW.conversation_id, 'message_id', NEW.id)
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create the BEFORE INSERT trigger on public.messages
DROP TRIGGER IF EXISTS trigger_handle_new_message ON public.messages;
CREATE TRIGGER trigger_handle_new_message
  BEFORE INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_message();

-- Enable Supabase Realtime for messages and notifications tables
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;
  
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
END $$;

-- ============================================================
-- MIGRATION: Add thumbnail_url to products (run on existing DBs)
-- ============================================================
-- If you already have a products table, run just this statement:
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS video_urls TEXT[] DEFAULT '{}';

-- ============================================================
-- MIGRATION: Purchase Permissions
-- ============================================================
CREATE TABLE IF NOT EXISTS public.purchase_permissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code VARCHAR(6) UNIQUE NOT NULL,
  customer_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  seller_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'granted', 'used', 'expired', 'revoked')),
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_purchase_permissions_code ON public.purchase_permissions(code);
CREATE INDEX IF NOT EXISTS idx_purchase_permissions_customer ON public.purchase_permissions(customer_id);
CREATE INDEX IF NOT EXISTS idx_purchase_permissions_product ON public.purchase_permissions(product_id);
CREATE INDEX IF NOT EXISTS idx_purchase_permissions_seller ON public.purchase_permissions(seller_id);

ALTER TABLE public.purchase_permissions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own permissions"
  ON public.purchase_permissions FOR SELECT
  TO authenticated
  USING (auth.uid() = customer_id OR auth.uid() = seller_id);

CREATE POLICY "Customers can insert own permissions"
  ON public.purchase_permissions FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = customer_id);

CREATE POLICY "Sellers can update own permissions"
  ON public.purchase_permissions FOR UPDATE
  TO authenticated
  USING (auth.uid() = seller_id);

CREATE TRIGGER trigger_purchase_permissions_updated_at
  BEFORE UPDATE ON public.purchase_permissions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE FUNCTION public.handle_purchase_permission_revocation()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE public.purchase_permissions
  SET status = 'used',
      updated_at = NOW()
  WHERE customer_id = (SELECT buyer_id FROM public.orders WHERE id = NEW.order_id)
    AND product_id = NEW.product_id
    AND status = 'granted';
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trigger_revoke_permission_on_purchase
  AFTER INSERT ON public.order_items
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_purchase_permission_revocation();


-- ============================================================
-- MIGRATION: Wallet Transaction SMS Notification Trigger
-- ============================================================

-- Create trigger function to send SMS on wallet transactions
CREATE OR REPLACE FUNCTION public.send_wallet_transaction_sms()
RETURNS TRIGGER AS $$
DECLARE
  v_url TEXT;
  v_anon_key TEXT;
  v_request_id BIGINT;
  v_phone_number TEXT;
  v_full_name TEXT;
  v_sms_content TEXT;
  v_amount_formatted TEXT;
  v_balance_formatted TEXT;
BEGIN
  -- 1. Fetch user phone number and name
  SELECT u.phone_number, u.full_name INTO v_phone_number, v_full_name
  FROM public.users u
  JOIN public.wallets w ON w.user_id = u.id
  WHERE w.id = NEW.wallet_id;

  -- If there's no phone number, we can't send SMS
  IF v_phone_number IS NULL OR v_phone_number = '' THEN
    RETURN NEW;
  END IF;

  -- 2. Normalize phone number (remove non-digits except '+', prepend +233 if starting with 0)
  v_phone_number := regexp_replace(v_phone_number, '[^\d+]', '', 'g');
  IF v_phone_number LIKE '0%' THEN
    v_phone_number := '+233' || substr(v_phone_number, 2);
  ELSIF v_phone_number NOT LIKE '+%' AND v_phone_number <> '' THEN
    v_phone_number := '+' || v_phone_number;
  END IF;

  -- 3. Fetch API keys from config
  SELECT value INTO v_url FROM public._push_trigger_config WHERE key = 'supabase_url';
  SELECT value INTO v_anon_key FROM public._push_trigger_config WHERE key = 'anon_key';

  IF v_url IS NULL OR v_anon_key IS NULL THEN
    RAISE LOG 'Wallet transaction SMS trigger: config not set';
    RETURN NEW;
  END IF;

  v_amount_formatted := to_char(NEW.amount, 'FM999,999,990.00');
  v_balance_formatted := to_char(NEW.balance_after, 'FM999,999,990.00');

  -- 4. Construct SMS content based on transaction type
  CASE NEW.type
    WHEN 'deposit' THEN
      v_sms_content := 'Hi ' || v_full_name || ', your wallet has been credited with GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'withdrawal' THEN
      v_sms_content := 'Hi ' || v_full_name || ', your withdrawal of GHS ' || v_amount_formatted || ' has been processed. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'transfer_out' THEN
      v_sms_content := 'Hi ' || v_full_name || ', you have successfully sent GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'transfer_in' THEN
      v_sms_content := 'Hi ' || v_full_name || ', you have received GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'payment' THEN
      v_sms_content := 'Hi ' || v_full_name || ', your payment of GHS ' || v_amount_formatted || ' was successful. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    WHEN 'refund' THEN
      v_sms_content := 'Hi ' || v_full_name || ', you have received a refund of GHS ' || v_amount_formatted || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '. Thank you for using Instiy!';
    ELSE
      v_sms_content := 'Hi ' || v_full_name || ', a wallet transaction of GHS ' || v_amount_formatted || ' occurred. Type: ' || NEW.type || '. New Balance: GHS ' || v_balance_formatted || '. Ref: ' || COALESCE(NEW.reference, 'N/A') || '.';
  END CASE;

  -- 5. Invoke Edge Function via pg_net
  SELECT net.http_post(
    url := v_url || '/functions/v1/send-sms',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key
    ),
    body := jsonb_build_object(
      'to', v_phone_number,
      'content', v_sms_content
    )
  ) INTO v_request_id;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Bind the trigger to the wallet_transactions table
DROP TRIGGER IF EXISTS trigger_wallet_transaction_sms ON public.wallet_transactions;
CREATE TRIGGER trigger_wallet_transaction_sms
  AFTER INSERT ON public.wallet_transactions
  FOR EACH ROW
  EXECUTE FUNCTION public.send_wallet_transaction_sms();

