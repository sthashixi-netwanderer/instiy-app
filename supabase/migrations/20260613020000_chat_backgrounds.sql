-- Create Chat Backgrounds table to customize backgrounds per user/conversation
CREATE TABLE IF NOT EXISTS public.chat_backgrounds (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE NOT NULL,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE,
  background_type TEXT NOT NULL CHECK (background_type IN ('none', 'gradient', 'image')),
  gradient_name TEXT,
  image_url TEXT,
  blur_intensity DOUBLE PRECISION DEFAULT 0.0 CHECK (blur_intensity >= 0.0 AND blur_intensity <= 30.0),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(user_id, conversation_id)
);

-- Enable RLS
ALTER TABLE public.chat_backgrounds ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "Users can view their own chat backgrounds"
  ON public.chat_backgrounds FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can manage their own chat backgrounds"
  ON public.chat_backgrounds
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Trigger to update updated_at
DROP TRIGGER IF EXISTS trigger_chat_backgrounds_updated_at ON public.chat_backgrounds;
CREATE TRIGGER trigger_chat_backgrounds_updated_at
  BEFORE UPDATE ON public.chat_backgrounds
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();
