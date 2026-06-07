-- Fix get_seller_store_reviews to only return top-level reviews (not replies as separate rows)
CREATE OR REPLACE FUNCTION get_seller_store_reviews(
  p_seller_id UUID,
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 20
)
RETURNS TABLE (
  id UUID,
  product_id UUID,
  reviewer_id UUID,
  rating INT,
  comment TEXT,
  media_urls TEXT[],
  helpful_count INT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  reviewer_name TEXT,
  reviewer_avatar TEXT,
  product_title TEXT,
  product_thumbnail TEXT,
  reply TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pr.id,
    pr.product_id,
    pr.reviewer_id,
    pr.rating,
    pr.comment,
    pr.media_urls,
    pr.helpful_count,
    pr.created_at,
    pr.updated_at,
    u.full_name AS reviewer_name,
    u.avatar_url AS reviewer_avatar,
    p.title AS product_title,
    CASE
      WHEN p.image_urls IS NOT NULL AND array_length(p.image_urls, 1) > 0
      THEN p.image_urls[1]
      ELSE p.thumbnail_url
    END AS product_thumbnail,
    (SELECT prr.reply FROM public.product_review_replies prr WHERE prr.review_id = pr.id LIMIT 1) AS reply
  FROM public.product_reviews pr
  JOIN public.products p ON p.id = pr.product_id
  JOIN public.users u ON u.id = pr.reviewer_id
  WHERE p.seller_id = p_seller_id AND pr.parent_id IS NULL
  ORDER BY pr.created_at DESC
  OFFSET p_offset
  LIMIT p_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
