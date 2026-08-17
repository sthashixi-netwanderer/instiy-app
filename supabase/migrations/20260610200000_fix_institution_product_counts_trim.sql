-- Migration: Fix get_institution_product_counts to trim whitespace from comma-split campus values
-- Without trim, "KNUST, University of Ghana" splits to ['KNUST', ' University of Ghana']
-- and the leading space causes name mismatches, showing incorrect product counts

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
  LEFT JOIN products p ON i.name IN (SELECT trim(v) FROM unnest(string_to_array(p.campus, ', ')) v)
    AND p.status = 'available'
    AND p.stock_quantity > 0
  GROUP BY i.id, i.code, i.name, i.logo_url, i.location
  ORDER BY i.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
