-- Carousel Slides for Home Screen
CREATE TABLE IF NOT EXISTS public.carousel_slides (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  media_url TEXT NOT NULL,
  media_type TEXT NOT NULL DEFAULT 'image' CHECK (media_type IN ('image', 'video', 'gif')),
  thumbnail_url TEXT,
  title TEXT,
  subtitle TEXT,
  button_text TEXT,
  button_link_type TEXT CHECK (button_link_type IN ('product', 'category', 'url')),
  button_link_value TEXT,
  is_visible BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_carousel_slides_sort_order ON public.carousel_slides(sort_order);
CREATE INDEX IF NOT EXISTS idx_carousel_slides_visible ON public.carousel_slides(is_visible);

ALTER TABLE public.carousel_slides ENABLE ROW LEVEL SECURITY;

-- Public read for visible slides
DROP POLICY IF EXISTS "Carousel slides are viewable by everyone" ON public.carousel_slides;
CREATE POLICY "Carousel slides are viewable by everyone"
  ON public.carousel_slides FOR SELECT
  USING (true);

-- Admin-only insert
DROP POLICY IF EXISTS "Admins can insert carousel slides" ON public.carousel_slides;
CREATE POLICY "Admins can insert carousel slides"
  ON public.carousel_slides FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin(auth.uid()));

-- Admin-only update
DROP POLICY IF EXISTS "Admins can update carousel slides" ON public.carousel_slides;
CREATE POLICY "Admins can update carousel slides"
  ON public.carousel_slides FOR UPDATE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- Admin-only delete
DROP POLICY IF EXISTS "Admins can delete carousel slides" ON public.carousel_slides;
CREATE POLICY "Admins can delete carousel slides"
  ON public.carousel_slides FOR DELETE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- updated_at trigger
DROP TRIGGER IF EXISTS trigger_carousel_slides_updated_at ON public.carousel_slides;
CREATE TRIGGER trigger_carousel_slides_updated_at
  BEFORE UPDATE ON public.carousel_slides
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Enable Realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'carousel_slides'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.carousel_slides;
  END IF;
END $$;

-- Admin RPC: Get all carousel slides with product/category names for display
CREATE OR REPLACE FUNCTION get_admin_carousel_slides()
RETURNS TABLE (
  id UUID,
  media_url TEXT,
  media_type TEXT,
  thumbnail_url TEXT,
  title TEXT,
  subtitle TEXT,
  button_text TEXT,
  button_link_type TEXT,
  button_link_value TEXT,
  is_visible BOOLEAN,
  sort_order INT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  linked_product_title TEXT,
  linked_category_name TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    cs.id,
    cs.media_url,
    cs.media_type,
    cs.thumbnail_url,
    cs.title,
    cs.subtitle,
    cs.button_text,
    cs.button_link_type,
    cs.button_link_value,
    cs.is_visible,
    cs.sort_order,
    cs.created_at,
    cs.updated_at,
    p.title AS linked_product_title,
    cat.name AS linked_category_name
  FROM public.carousel_slides cs
  LEFT JOIN public.products p ON cs.button_link_type = 'product' AND p.id = cs.button_link_value::UUID
  LEFT JOIN public.categories cat ON cs.button_link_type = 'category' AND cat.id = cs.button_link_value::UUID
  ORDER BY cs.sort_order ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
