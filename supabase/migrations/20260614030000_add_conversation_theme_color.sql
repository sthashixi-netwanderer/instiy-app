-- Add theme_color column to conversations table
ALTER TABLE public.conversations
ADD COLUMN IF NOT EXISTS theme_color TEXT;
