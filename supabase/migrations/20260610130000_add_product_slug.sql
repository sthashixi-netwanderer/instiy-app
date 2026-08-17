-- Add slug column to products table for SEO-friendly URLs
-- slug format: product-name-slug (URL-safe, derived from title)

-- 1. Add slug column (nullable initially for backfill)
ALTER TABLE products ADD COLUMN slug TEXT;

-- 2. Backfill existing products: generate slug from title
-- Same logic as Product.generateSlug() in Dart:
--   lowercase, remove non-alphanumeric (keep hyphens), spaces→hyphens, collapse hyphens, trim
UPDATE products
SET slug = lower(regexp_replace(regexp_replace(regexp_replace(regexp_replace(title, '[^a-zA-Z0-9\s-]', '', 'g'), '\s+', '-', 'g'), '-+', '-', 'g'), '^-|-$', '', 'g'));

-- 3. Handle potential slug collisions by appending a short suffix of the id
-- For products with duplicate slugs, keep the first occurrence and append id suffix to duplicates
WITH ranked AS (
  SELECT id, slug, row_number() OVER (PARTITION BY slug ORDER BY created_at) AS rn
  FROM products
  WHERE slug IS NOT NULL
)
UPDATE products p
SET slug = p.slug || '-' || substr(r.id::text, 1, 8)
FROM ranked r
WHERE p.id = r.id AND r.rn > 1;

-- 4. Add NOT NULL constraint (all rows now have slugs)
ALTER TABLE products ALTER COLUMN slug SET NOT NULL;

-- 5. Add unique index for slug lookups
CREATE UNIQUE INDEX idx_products_slug ON products (slug);

-- 6. Add a trigger to auto-generate slug on insert/update if slug is not provided
CREATE OR REPLACE FUNCTION generate_product_slug()
RETURNS TRIGGER AS $$
DECLARE
  base_slug TEXT;
  candidate_slug TEXT;
  counter INT := 0;
BEGIN
  -- Only generate slug if not explicitly provided
  IF NEW.slug IS NULL OR NEW.slug = '' THEN
    base_slug := lower(regexp_replace(regexp_replace(regexp_replace(regexp_replace(NEW.title, '[^a-zA-Z0-9\s-]', '', 'g'), '\s+', '-', 'g'), '-+', '-', 'g'), '^-|-$', '', 'g'));
    candidate_slug := base_slug;

    -- Check for collisions and append suffix if needed
    WHILE EXISTS (SELECT 1 FROM products WHERE slug = candidate_slug AND id != NEW.id) LOOP
      counter := counter + 1;
      candidate_slug := base_slug || '-' || substr(NEW.id::text, 1, 8);
      IF counter > 1 THEN
        candidate_slug := candidate_slug || '-' || counter;
      END IF;
    END LOOP;

    NEW.slug := candidate_slug;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_generate_product_slug
  BEFORE INSERT OR UPDATE OF title ON products
  FOR EACH ROW
  EXECUTE FUNCTION generate_product_slug();
