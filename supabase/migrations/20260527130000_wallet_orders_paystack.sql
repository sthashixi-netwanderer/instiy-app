-- Wallets
CREATE TABLE IF NOT EXISTS public.wallets (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL UNIQUE,
  balance DECIMAL(12, 2) DEFAULT 0 NOT NULL,
  currency TEXT DEFAULT 'GHS',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallets_user_id ON public.wallets(user_id);

-- Wallet transactions
CREATE TABLE IF NOT EXISTS public.wallet_transactions (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  wallet_id UUID REFERENCES public.wallets(id) ON DELETE CASCADE NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('deposit', 'withdrawal', 'transfer_in', 'transfer_out', 'payment', 'refund')),
  amount DECIMAL(12, 2) NOT NULL,
  balance_before DECIMAL(12, 2) NOT NULL,
  balance_after DECIMAL(12, 2) NOT NULL,
  description TEXT,
  reference TEXT,
  source TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_wallet_tx_wallet_id ON public.wallet_transactions(wallet_id);
CREATE INDEX IF NOT EXISTS idx_wallet_tx_created_at ON public.wallet_transactions(created_at DESC);

-- Withdrawal requests
CREATE TABLE IF NOT EXISTS public.withdrawal_requests (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  amount_requested DECIMAL(12, 2) NOT NULL,
  fee_amount DECIMAL(12, 2),
  amount_to_receive DECIMAL(12, 2),
  method_type TEXT NOT NULL CHECK (method_type IN ('mobile_money', 'bank', 'paystack')),
  provider_type TEXT,
  account_details TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  admin_notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_withdrawal_requests_user_id ON public.withdrawal_requests(user_id);

-- Orders
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  buyer_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  total_amount DECIMAL(12, 2) NOT NULL,
  item_quantity_total INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'processing', 'shipped', 'delivered', 'cancelled', 'refunded')),
  payment_status TEXT NOT NULL DEFAULT 'unpaid' CHECK (payment_status IN ('unpaid', 'paid', 'refunded', 'failed')),
  payment_method TEXT DEFAULT 'wallet',
  payment_reference TEXT,
  delivery_mode TEXT CHECK (delivery_mode IN ('pickup', 'delivery')),
  delivery_fee DECIMAL(10, 2) DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_orders_buyer_id ON public.orders(buyer_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON public.orders(created_at DESC);

-- Order items
CREATE TABLE IF NOT EXISTS public.order_items (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
  product_title TEXT NOT NULL,
  product_thumbnail TEXT,
  quantity INTEGER NOT NULL DEFAULT 1,
  price DECIMAL(10, 2) NOT NULL,
  delivery_code TEXT,
  status TEXT DEFAULT 'pending',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON public.order_items(order_id);

-- Cart (user_carts)
CREATE TABLE IF NOT EXISTS public.user_carts (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE NOT NULL,
  quantity INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_user_carts_user_id ON public.user_carts(user_id);

-- Notifications
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT,
  data JSONB,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications(user_id, is_read) WHERE is_read = false;

-- Conversations
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  participant1_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  participant2_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  last_message TEXT,
  last_message_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE (participant1_id, participant2_id)
);

CREATE INDEX IF NOT EXISTS idx_conversations_p1 ON public.conversations(participant1_id);
CREATE INDEX IF NOT EXISTS idx_conversations_p2 ON public.conversations(participant2_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_msg ON public.conversations(last_message_at DESC);

-- Messages
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE NOT NULL,
  sender_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  receiver_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  content TEXT NOT NULL,
  is_read BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON public.messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver_unread ON public.messages(receiver_id, is_read) WHERE is_read = false;

-- Services
CREATE TABLE IF NOT EXISTS public.services (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  provider_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  description TEXT,
  category TEXT,
  price DECIMAL(10, 2) NOT NULL,
  price_type TEXT DEFAULT 'fixed' CHECK (price_type IN ('fixed', 'hourly', 'negotiable')),
  image_urls TEXT[] DEFAULT '{}',
  institution_codes TEXT[] DEFAULT '{}',
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'paused')),
  average_rating DECIMAL(3, 2) DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_services_provider_id ON public.services(provider_id);
CREATE INDEX IF NOT EXISTS idx_services_category ON public.services(category);
CREATE INDEX IF NOT EXISTS idx_services_status ON public.services(status);

-- =====================================
-- RLS
-- =====================================
ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawal_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_carts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

-- Wallets: users can view own wallet
DROP POLICY IF EXISTS "Users can view own wallet" ON public.wallets;
CREATE POLICY "Users can view own wallet"
  ON public.wallets FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Service can insert wallet" ON public.wallets;
CREATE POLICY "Service can insert wallet"
  ON public.wallets FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Wallet transactions: users can view own transactions
DROP POLICY IF EXISTS "Users can view own transactions" ON public.wallet_transactions;
CREATE POLICY "Users can view own transactions"
  ON public.wallet_transactions FOR SELECT
  TO authenticated
  USING (wallet_id IN (SELECT id FROM public.wallets WHERE user_id = auth.uid()));

-- Withdrawal requests: users can view/manage own
DROP POLICY IF EXISTS "Users can view own withdrawal requests" ON public.withdrawal_requests;
CREATE POLICY "Users can view own withdrawal requests"
  ON public.withdrawal_requests FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can create own withdrawal requests" ON public.withdrawal_requests;
CREATE POLICY "Users can create own withdrawal requests"
  ON public.withdrawal_requests FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- Orders: buyers can view own orders
DROP POLICY IF EXISTS "Buyers can view own orders" ON public.orders;
CREATE POLICY "Buyers can view own orders"
  ON public.orders FOR SELECT
  TO authenticated
  USING (auth.uid() = buyer_id);

-- Order items: view through order ownership
DROP POLICY IF EXISTS "Users can view own order items" ON public.order_items;
CREATE POLICY "Users can view own order items"
  ON public.order_items FOR SELECT
  TO authenticated
  USING (order_id IN (SELECT id FROM public.orders WHERE buyer_id = auth.uid()));

-- Cart: users can manage own cart
DROP POLICY IF EXISTS "Users can view own cart" ON public.user_carts;
CREATE POLICY "Users can view own cart"
  ON public.user_carts FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own cart" ON public.user_carts;
CREATE POLICY "Users can insert own cart"
  ON public.user_carts FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own cart" ON public.user_carts;
CREATE POLICY "Users can update own cart"
  ON public.user_carts FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own cart" ON public.user_carts;
CREATE POLICY "Users can delete own cart"
  ON public.user_carts FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Notifications: users can view own
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
CREATE POLICY "Users can view own notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;
CREATE POLICY "Users can update own notifications"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id);

-- Conversations: participants can view
DROP POLICY IF EXISTS "Participants can view conversations" ON public.conversations;
CREATE POLICY "Participants can view conversations"
  ON public.conversations FOR SELECT
  TO authenticated
  USING (auth.uid() = participant1_id OR auth.uid() = participant2_id);

DROP POLICY IF EXISTS "Participants can insert conversations" ON public.conversations;
CREATE POLICY "Participants can insert conversations"
  ON public.conversations FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() IN (participant1_id, participant2_id));

-- Messages: participants can view
DROP POLICY IF EXISTS "Participants can view messages" ON public.messages;
CREATE POLICY "Participants can view messages"
  ON public.messages FOR SELECT
  TO authenticated
  USING (conversation_id IN (
    SELECT id FROM public.conversations
    WHERE participant1_id = auth.uid() OR participant2_id = auth.uid()
  ));

DROP POLICY IF EXISTS "Participants can send messages" ON public.messages;
CREATE POLICY "Participants can send messages"
  ON public.messages FOR INSERT
  TO authenticated
  WITH CHECK (
    conversation_id IN (
      SELECT id FROM public.conversations
      WHERE participant1_id = auth.uid() OR participant2_id = auth.uid()
    )
    AND sender_id = auth.uid()
  );

DROP POLICY IF EXISTS "Participants can update messages" ON public.messages;
CREATE POLICY "Participants can update messages"
  ON public.messages FOR UPDATE
  TO authenticated
  USING (conversation_id IN (
    SELECT id FROM public.conversations
    WHERE participant1_id = auth.uid() OR participant2_id = auth.uid()
  ));

-- Services: any authenticated user can view
DROP POLICY IF EXISTS "Users can view services" ON public.services;
CREATE POLICY "Users can view services"
  ON public.services FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Providers can create services" ON public.services;
CREATE POLICY "Providers can create services"
  ON public.services FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = provider_id);

DROP POLICY IF EXISTS "Providers can update own services" ON public.services;
CREATE POLICY "Providers can update own services"
  ON public.services FOR UPDATE
  TO authenticated
  USING (auth.uid() = provider_id);

-- =====================================
-- PROFILES VIEW (Supabase convention)
-- =====================================
CREATE OR REPLACE VIEW public.profiles AS
  SELECT id AS user_id, id, email, full_name, avatar_url, university, bio, phone_number, created_at, updated_at
  FROM public.users;

-- =====================================
-- TRIGGERS
-- =====================================
CREATE OR REPLACE FUNCTION public.handle_new_user_wallet()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.wallets (user_id, balance, currency)
  VALUES (NEW.id, 0, 'GHS');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_user_created_create_wallet ON public.users;
CREATE TRIGGER on_user_created_create_wallet
  AFTER INSERT ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_user_wallet();

-- =====================================
-- RPC FUNCTIONS
-- =====================================

-- Credit wallet (add funds)
CREATE OR REPLACE FUNCTION public.credit_wallet(
  p_user_id UUID,
  p_amount DECIMAL,
  p_reference TEXT DEFAULT NULL,
  p_description TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_wallet_id UUID;
  v_old_balance DECIMAL(12, 2);
BEGIN
  SELECT id, balance INTO v_wallet_id, v_old_balance
  FROM public.wallets WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE public.wallets
  SET balance = balance + p_amount, updated_at = NOW()
  WHERE id = v_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, type, amount, balance_before, balance_after, description, reference, source)
  VALUES
    (v_wallet_id, 'deposit', p_amount, v_old_balance, v_old_balance + p_amount, p_description, p_reference, 'paystack');

  RETURN TRUE;
END;
$$;

-- Deduct wallet (with balance check)
CREATE OR REPLACE FUNCTION public.deduct_wallet(
  p_user_id UUID,
  p_amount DECIMAL,
  p_description TEXT DEFAULT NULL,
  p_reference TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_wallet_id UUID;
  v_balance DECIMAL(12, 2);
  v_pending DECIMAL(12, 2);
BEGIN
  SELECT id, balance INTO v_wallet_id, v_balance
  FROM public.wallets WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_wallet_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT COALESCE(SUM(amount_requested), 0) INTO v_pending
  FROM public.withdrawal_requests
  WHERE user_id = p_user_id AND status IN ('pending', 'processing');

  IF (v_balance - v_pending) < p_amount THEN
    RETURN FALSE;
  END IF;

  UPDATE public.wallets
  SET balance = balance - p_amount, updated_at = NOW()
  WHERE id = v_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, type, amount, balance_before, balance_after, description, reference, source)
  VALUES
    (v_wallet_id, 'payment', p_amount, v_balance, v_balance - p_amount, p_description, p_reference, 'order');

  RETURN TRUE;
END;
$$;

-- Get pending balance (sum of pending withdrawals)
CREATE OR REPLACE FUNCTION public.get_pending_balance(p_user_id UUID)
RETURNS DECIMAL
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_pending DECIMAL(12, 2);
BEGIN
  SELECT COALESCE(SUM(amount_requested), 0) INTO v_pending
  FROM public.withdrawal_requests
  WHERE user_id = p_user_id AND status IN ('pending', 'processing');

  RETURN v_pending;
END;
$$;

-- Transfer wallet funds between users
CREATE OR REPLACE FUNCTION public.transfer_wallet_funds(
  recipient_id UUID,
  amount DECIMAL,
  description TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_sender_wallet_id UUID;
  v_sender_balance DECIMAL(12, 2);
  v_recipient_wallet_id UUID;
  v_recipient_balance DECIMAL(12, 2);
  v_pending DECIMAL(12, 2);
BEGIN
  SELECT id, balance INTO v_sender_wallet_id, v_sender_balance
  FROM public.wallets WHERE user_id = auth.uid()
  FOR UPDATE;

  IF v_sender_wallet_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT COALESCE(SUM(amount_requested), 0) INTO v_pending
  FROM public.withdrawal_requests
  WHERE user_id = auth.uid() AND status IN ('pending', 'processing');

  IF (v_sender_balance - v_pending) < amount THEN
    RETURN FALSE;
  END IF;

  SELECT id, balance INTO v_recipient_wallet_id, v_recipient_balance
  FROM public.wallets WHERE user_id = recipient_id
  FOR UPDATE;

  IF v_recipient_wallet_id IS NULL THEN
    RETURN FALSE;
  END IF;

  UPDATE public.wallets
  SET balance = balance - amount, updated_at = NOW()
  WHERE id = v_sender_wallet_id;

  UPDATE public.wallets
  SET balance = balance + amount, updated_at = NOW()
  WHERE id = v_recipient_wallet_id;

  INSERT INTO public.wallet_transactions
    (wallet_id, type, amount, balance_before, balance_after, description, source)
  VALUES
    (v_sender_wallet_id, 'transfer_out', amount, v_sender_balance, v_sender_balance - amount, description, 'transfer'),
    (v_recipient_wallet_id, 'transfer_in', amount, v_recipient_balance, v_recipient_balance + amount, description, 'transfer');

  RETURN TRUE;
END;
$$;

-- Create order from cart (clears cart after)
CREATE OR REPLACE FUNCTION public.create_order(
  p_buyer_id UUID,
  p_delivery_mode TEXT DEFAULT 'pickup',
  p_payment_method TEXT DEFAULT 'wallet',
  p_payment_reference TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_order_id UUID;
  v_total DECIMAL(12, 2);
  v_item_count INTEGER;
  v_cart_item RECORD;
BEGIN
  -- Calculate total and count
  SELECT COALESCE(SUM(p.price * c.quantity), 0), COALESCE(SUM(c.quantity), 0)
  INTO v_total, v_item_count
  FROM public.user_carts c
  JOIN public.products p ON p.id = c.product_id
  WHERE c.user_id = p_buyer_id;

  IF v_item_count = 0 THEN
    RAISE EXCEPTION 'Cart is empty';
  END IF;

  -- Create order
  INSERT INTO public.orders
    (buyer_id, total_amount, item_quantity_total, delivery_mode, payment_method, payment_reference, status, payment_status)
  VALUES
    (p_buyer_id, v_total, v_item_count, p_delivery_mode, p_payment_method, p_payment_reference, 'pending', 'unpaid')
  RETURNING id INTO v_order_id;

  -- Create order items from cart
  FOR v_cart_item IN
    SELECT c.quantity, p.id AS product_id, p.title, p.image_urls, p.price
    FROM public.user_carts c
    JOIN public.products p ON p.id = c.product_id
    WHERE c.user_id = p_buyer_id
  LOOP
    INSERT INTO public.order_items
      (order_id, product_id, product_title, product_thumbnail, quantity, price)
    VALUES
      (v_order_id, v_cart_item.product_id, v_cart_item.title,
       CASE WHEN array_length(v_cart_item.image_urls, 1) > 0 THEN v_cart_item.image_urls[1] ELSE NULL END,
       v_cart_item.quantity, v_cart_item.price);
  END LOOP;

  -- Clear cart
  DELETE FROM public.user_carts WHERE user_id = p_buyer_id;

  RETURN v_order_id;
END;
$$;

-- Mark order as paid
CREATE OR REPLACE FUNCTION public.mark_order_paid(
  p_order_id UUID,
  p_reference TEXT DEFAULT NULL
) RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.orders
  SET payment_status = 'paid',
      payment_reference = COALESCE(p_reference, payment_reference),
      status = 'confirmed',
      updated_at = NOW()
  WHERE id = p_order_id;

  RETURN FOUND;
END;
$$;

-- Cancel order
CREATE OR REPLACE FUNCTION public.cancel_order(order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_buyer_id UUID;
  v_total DECIMAL(12, 2);
  v_payment_status TEXT;
BEGIN
  SELECT buyer_id, total_amount, payment_status
  INTO v_buyer_id, v_total, v_payment_status
  FROM public.orders WHERE id = order_id;

  IF v_buyer_id IS NULL THEN
    RETURN FALSE;
  END IF;

  IF v_payment_status = 'paid' THEN
    PERFORM public.credit_wallet(v_buyer_id, v_total, 'REFUND-' || order_id, 'Refund for cancelled order ' || order_id);
  END IF;

  UPDATE public.orders
  SET status = 'cancelled', updated_at = NOW()
  WHERE id = order_id;

  RETURN TRUE;
END;
$$;

-- =====================================
-- UPDATED_AT TRIGGERS
-- =====================================
DROP TRIGGER IF EXISTS trigger_wallets_updated_at ON public.wallets;
CREATE TRIGGER trigger_wallets_updated_at
  BEFORE UPDATE ON public.wallets
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_orders_updated_at ON public.orders;
CREATE TRIGGER trigger_orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS trigger_services_updated_at ON public.services;
CREATE TRIGGER trigger_services_updated_at
  BEFORE UPDATE ON public.services
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
