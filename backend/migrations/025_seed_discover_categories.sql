-- Seed discoverable marketplace categories. Slugs make this safe to re-run on deploy.
INSERT INTO categories (name, slug) VALUES
  ('Electronics', 'electronics'),
  ('Fashion', 'fashion'),
  ('Home & Living', 'home-living'),
  ('Beauty', 'beauty'),
  ('Health', 'health'),
  ('Food & Groceries', 'food-groceries'),
  ('Vehicles', 'vehicles'),
  ('Sports & Outdoors', 'sports-outdoors'),
  ('Books & Learning', 'books-learning'),
  ('Gaming', 'gaming'),
  ('Pets', 'pets'),
  ('Baby & Kids', 'baby-kids'),
  ('Tools & Hardware', 'tools-hardware')
ON CONFLICT (slug) DO NOTHING;
