-- Migration: Automatic Product Status Synchronization based on Stock Quantity
-- This trigger automatically handles changing the status from 'sold' to 'available'
-- when a product is added or edited to have a positive stock quantity.

CREATE OR REPLACE FUNCTION public.handle_product_stock_status_sync()
RETURNS TRIGGER AS $$
BEGIN
  -- If stock quantity is greater than 0 and status is 'sold', change it to 'available'
  IF NEW.stock_quantity > 0 AND NEW.status = 'sold' THEN
    NEW.status := 'available';
  END IF;

  -- If stock quantity is 0 and status is 'available', change it to 'sold'
  IF NEW.stock_quantity = 0 AND NEW.status = 'available' THEN
    NEW.status := 'sold';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to products table
DROP TRIGGER IF EXISTS trigger_handle_product_stock_status_sync ON public.products;
CREATE TRIGGER trigger_handle_product_stock_status_sync
  BEFORE INSERT OR UPDATE ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_product_stock_status_sync();
