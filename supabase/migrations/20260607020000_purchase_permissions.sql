-- Create purchase_permissions table
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

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_purchase_permissions_code ON public.purchase_permissions(code);
CREATE INDEX IF NOT EXISTS idx_purchase_permissions_customer ON public.purchase_permissions(customer_id);
CREATE INDEX IF NOT EXISTS idx_purchase_permissions_product ON public.purchase_permissions(product_id);
CREATE INDEX IF NOT EXISTS idx_purchase_permissions_seller ON public.purchase_permissions(seller_id);

-- Enable RLS
ALTER TABLE public.purchase_permissions ENABLE ROW LEVEL SECURITY;

-- Select policy
CREATE POLICY "Users can view own permissions"
  ON public.purchase_permissions FOR SELECT
  TO authenticated
  USING (auth.uid() = customer_id OR auth.uid() = seller_id);

-- Insert policy (only customer can create)
CREATE POLICY "Customers can insert own permissions"
  ON public.purchase_permissions FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = customer_id);

-- Update policy (only seller can update)
CREATE POLICY "Sellers can update own permissions"
  ON public.purchase_permissions FOR UPDATE
  TO authenticated
  USING (auth.uid() = seller_id);

-- Trigger to update updated_at column
CREATE TRIGGER trigger_purchase_permissions_updated_at
  BEFORE UPDATE ON public.purchase_permissions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Function to handle purchase permission revocation when order is created
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

-- Trigger to revoke permission on purchase
DROP TRIGGER IF EXISTS trigger_revoke_permission_on_purchase ON public.order_items;
CREATE TRIGGER trigger_revoke_permission_on_purchase
  AFTER INSERT ON public.order_items
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_purchase_permission_revocation();
