-- Curated Collections
CREATE TABLE IF NOT EXISTS public.curated_collections (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  title TEXT NOT NULL,
  subtitle TEXT,
  icon TEXT,
  image_url TEXT,
  display_mode TEXT NOT NULL DEFAULT 'horizontal' CHECK (display_mode IN ('horizontal', 'grid')),
  content_type TEXT NOT NULL DEFAULT 'products' CHECK (content_type IN ('products', 'categories')),
  max_items INT NOT NULL DEFAULT 10,
  is_visible BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_curated_collections_sort_order ON public.curated_collections(sort_order);
CREATE INDEX IF NOT EXISTS idx_curated_collections_visible ON public.curated_collections(is_visible);

ALTER TABLE public.curated_collections ENABLE ROW LEVEL SECURITY;

-- Public read for visible collections
DROP POLICY IF EXISTS "Curated collections are viewable by everyone" ON public.curated_collections;
CREATE POLICY "Curated collections are viewable by everyone"
  ON public.curated_collections FOR SELECT
  USING (true);

-- Admin-only insert
DROP POLICY IF EXISTS "Admins can insert curated collections" ON public.curated_collections;
CREATE POLICY "Admins can insert curated collections"
  ON public.curated_collections FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin(auth.uid()));

-- Admin-only update
DROP POLICY IF EXISTS "Admins can update curated collections" ON public.curated_collections;
CREATE POLICY "Admins can update curated collections"
  ON public.curated_collections FOR UPDATE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- Admin-only delete
DROP POLICY IF EXISTS "Admins can delete curated collections" ON public.curated_collections;
CREATE POLICY "Admins can delete curated collections"
  ON public.curated_collections FOR DELETE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- updated_at trigger
DROP TRIGGER IF EXISTS trigger_curated_collections_updated_at ON public.curated_collections;
CREATE TRIGGER trigger_curated_collections_updated_at
  BEFORE UPDATE ON public.curated_collections
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Curated Collection Items
CREATE TABLE IF NOT EXISTS public.curated_collection_items (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  collection_id UUID REFERENCES public.curated_collections(id) ON DELETE CASCADE NOT NULL,
  product_id UUID REFERENCES public.products(id) ON DELETE CASCADE,
  category_id UUID REFERENCES public.categories(id) ON DELETE CASCADE,
  sort_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  CONSTRAINT curated_item_has_target CHECK (
    (product_id IS NOT NULL AND category_id IS NULL) OR
    (product_id IS NULL AND category_id IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_curated_items_collection_id ON public.curated_collection_items(collection_id);
CREATE INDEX IF NOT EXISTS idx_curated_items_product_id ON public.curated_collection_items(product_id);
CREATE INDEX IF NOT EXISTS idx_curated_items_category_id ON public.curated_collection_items(category_id);

ALTER TABLE public.curated_collection_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Curated items are viewable by everyone" ON public.curated_collection_items;
CREATE POLICY "Curated items are viewable by everyone"
  ON public.curated_collection_items FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Admins can insert curated items" ON public.curated_collection_items;
CREATE POLICY "Admins can insert curated items"
  ON public.curated_collection_items FOR INSERT
  TO authenticated
  WITH CHECK (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can update curated items" ON public.curated_collection_items;
CREATE POLICY "Admins can update curated items"
  ON public.curated_collection_items FOR UPDATE
  TO authenticated
  USING (public.is_admin(auth.uid()));

DROP POLICY IF EXISTS "Admins can delete curated items" ON public.curated_collection_items;
CREATE POLICY "Admins can delete curated items"
  ON public.curated_collection_items FOR DELETE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- Enable Realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'curated_collections'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.curated_collections;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'curated_collection_items'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.curated_collection_items;
  END IF;
END $$;

-- RPC: Get curated home sections with items
CREATE OR REPLACE FUNCTION get_curated_home_sections()
RETURNS TABLE (
  collection_id UUID,
  collection_title TEXT,
  collection_subtitle TEXT,
  collection_icon TEXT,
  collection_image_url TEXT,
  collection_display_mode TEXT,
  collection_content_type TEXT,
  collection_max_items INT,
  collection_sort_order INT,
  item_id UUID,
  item_sort_order INT,
  item_product_id UUID,
  item_category_id UUID,
  -- Product fields (nullable)
  product_title TEXT,
  product_price NUMERIC,
  product_thumbnail TEXT,
  product_image_urls TEXT[],
  product_seller_name TEXT,
  product_seller_avatar TEXT,
  product_is_seller_verified BOOLEAN,
  product_seller_university TEXT,
  product_condition TEXT,
  product_status TEXT,
  product_discount_percent NUMERIC,
  product_discount_start_date TIMESTAMPTZ,
  product_discount_end_date TIMESTAMPTZ,
  product_stock_quantity INT,
  product_campuses TEXT[],
  -- Category fields (nullable)
  category_name TEXT,
  category_icon TEXT,
  category_color_index INT,
  category_image_url TEXT,
  category_slug TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    cc.id AS collection_id,
    cc.title AS collection_title,
    cc.subtitle AS collection_subtitle,
    cc.icon AS collection_icon,
    cc.image_url AS collection_image_url,
    cc.display_mode AS collection_display_mode,
    cc.content_type AS collection_content_type,
    cc.max_items AS collection_max_items,
    cc.sort_order AS collection_sort_order,
    cci.id AS item_id,
    cci.sort_order AS item_sort_order,
    cci.product_id AS item_product_id,
    cci.category_id AS item_category_id,
    -- Product fields
    p.title AS product_title,
    p.price AS product_price,
    CASE
      WHEN p.image_urls IS NOT NULL AND array_length(p.image_urls, 1) > 0
      THEN p.image_urls[1]
      ELSE p.thumbnail_url
    END AS product_thumbnail,
    p.image_urls AS product_image_urls,
    u.full_name AS product_seller_name,
    u.avatar_url AS product_seller_avatar,
    u.is_verified AS product_is_seller_verified,
    u.university AS product_seller_university,
    p.condition::TEXT AS product_condition,
    p.status::TEXT AS product_status,
    COALESCE(p.discount_percent, 0) AS product_discount_percent,
    p.discount_start_date AS product_discount_start_date,
    p.discount_end_date AS product_discount_end_date,
    COALESCE(p.stock_quantity, 1) AS product_stock_quantity,
    COALESCE(p.campus, '{}') AS product_campuses,
    -- Category fields
    cat.name AS category_name,
    cat.icon AS category_icon,
    COALESCE(cat.color_index, 0) AS category_color_index,
    cat.image_url AS category_image_url,
    cat.slug AS category_slug
  FROM public.curated_collections cc
  JOIN public.curated_collection_items cci ON cci.collection_id = cc.id
  LEFT JOIN public.products p ON p.id = cci.product_id
  LEFT JOIN public.users u ON u.id = p.seller_id
  LEFT JOIN public.categories cat ON cat.id = cci.category_id
  WHERE cc.is_visible = true
  ORDER BY cc.sort_order ASC, cci.sort_order ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Admin RPC: Get all collections with item counts
CREATE OR REPLACE FUNCTION get_admin_curated_collections()
RETURNS TABLE (
  id UUID,
  title TEXT,
  subtitle TEXT,
  icon TEXT,
  image_url TEXT,
  display_mode TEXT,
  content_type TEXT,
  max_items INT,
  is_visible BOOLEAN,
  sort_order INT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  item_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    cc.id,
    cc.title,
    cc.subtitle,
    cc.icon,
    cc.image_url,
    cc.display_mode,
    cc.content_type,
    cc.max_items,
    cc.is_visible,
    cc.sort_order,
    cc.created_at,
    cc.updated_at,
    COUNT(cci.id) AS item_count
  FROM public.curated_collections cc
  LEFT JOIN public.curated_collection_items cci ON cci.collection_id = cc.id
  GROUP BY cc.id, cc.title, cc.subtitle, cc.icon, cc.image_url, cc.display_mode,
           cc.content_type, cc.max_items, cc.is_visible, cc.sort_order,
           cc.created_at, cc.updated_at
  ORDER BY cc.sort_order ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
