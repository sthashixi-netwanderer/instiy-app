-- Insert default categories
INSERT INTO public.categories (name, icon, color_index) VALUES
  ('Electronics', 'smartphone', 0),
  ('Textbooks', 'book', 1),
  ('Furniture', 'armchair', 2),
  ('Clothing', 'shirt', 3),
  ('Sports', 'dumbbell', 4),
  ('Music', 'music', 5),
  ('Gaming', 'gamepad', 6),
  ('Other', 'grid', 7)
ON CONFLICT (name) DO NOTHING;
