-- Migration: Align get_institution_product_counts with the explore screen filter
--
-- The explore grid filters products by campus using substring matching
-- (campus ILIKE '%<institution name>%', case-insensitive), while this RPC
-- counted only exact elements of the comma-split campus list (split on ', ',
-- case-sensitive). Products whose campus string merely contains an
-- institution name — e.g. "University of Ghana, Legon", values joined
-- without the ', ' separator, or differing case — appeared in the grid but
-- were never counted, so the badge number never matched the grid.
--
-- The RPC now uses the same ILIKE containment match as the grid so the
-- badge always equals the number of products the filter actually shows.
-- Status/stock conditions are unchanged (available + in stock on both sides).

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
  LEFT JOIN products p ON p.campus ILIKE '%' || i.name || '%'
    AND p.status = 'available'
    AND p.stock_quantity > 0
  GROUP BY i.id, i.code, i.name, i.logo_url, i.location
  ORDER BY i.name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
