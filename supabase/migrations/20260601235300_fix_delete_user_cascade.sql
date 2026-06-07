-- Fix order_items seller_id foreign key constraint to cascade on user deletion
ALTER TABLE public.order_items 
  DROP CONSTRAINT IF EXISTS order_items_seller_id_fkey,
  ADD CONSTRAINT order_items_seller_id_fkey 
    FOREIGN KEY (seller_id) 
    REFERENCES public.users(id) 
    ON DELETE CASCADE;

-- Fix seller_verifications reviewed_by foreign key constraint to set null on admin deletion
ALTER TABLE public.seller_verifications 
  DROP CONSTRAINT IF EXISTS seller_verifications_reviewed_by_fkey,
  ADD CONSTRAINT seller_verifications_reviewed_by_fkey 
    FOREIGN KEY (reviewed_by) 
    REFERENCES public.users(id) 
    ON DELETE SET NULL;
