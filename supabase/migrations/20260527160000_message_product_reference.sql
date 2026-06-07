-- Add product_reference column to messages table for WhatsApp-style product sharing
ALTER TABLE public.messages
ADD COLUMN IF NOT EXISTS product_reference JSONB;
