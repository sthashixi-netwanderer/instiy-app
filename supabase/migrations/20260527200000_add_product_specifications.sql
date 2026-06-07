ALTER TABLE products
ADD COLUMN specifications JSONB NOT NULL DEFAULT '[]'::jsonb;
