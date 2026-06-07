-- Fix: products.campus is TEXT, not TEXT[]. Wrap in ARRAY[] to match return type.

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
    p.discount_start_date::TIMESTAMPTZ AS product_discount_start_date,
    p.discount_end_date::TIMESTAMPTZ AS product_discount_end_date,
    COALESCE(p.stock_quantity, 1) AS product_stock_quantity,
    CASE
      WHEN p.campus IS NOT NULL AND p.campus != '' THEN ARRAY[p.campus]
      ELSE '{}'::TEXT[]
    END AS product_campuses,
    cat.name AS category_name,
    cat.icon AS category_icon,
    COALESCE(cat.color_index, 0) AS category_color_index,
    cat.image_url AS category_image_url,
    cat.slug AS category_slug
  FROM public.curated_collections cc
  LEFT JOIN public.curated_collection_items cci ON cci.collection_id = cc.id
  LEFT JOIN public.products p ON p.id = cci.product_id
  LEFT JOIN public.users u ON u.id = p.seller_id
  LEFT JOIN public.categories cat ON cat.id = cci.category_id
  WHERE cc.is_visible = true
  ORDER BY cc.sort_order ASC, cci.sort_order ASC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
