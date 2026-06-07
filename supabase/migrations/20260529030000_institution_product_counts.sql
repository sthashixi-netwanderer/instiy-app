-- RPC function to get institutions with product counts
CREATE OR REPLACE FUNCTION get_institution_product_counts()
RETURNS TABLE (
  id UUID,
  code TEXT,
  name TEXT,
  logo_url TEXT,
  location TEXT,
  product_count BIGINT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    i.id,
    i.code,
    i.name,
    i.logo_url,
    i.location,
    COUNT(p.id) AS product_count
  FROM institutions i
  LEFT JOIN products p ON p.campus @> ARRAY[i.name]
    AND p.status = 'available'
    AND p.stock_quantity > 0
  GROUP BY i.id, i.code, i.name, i.logo_url, i.location
  ORDER BY i.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
