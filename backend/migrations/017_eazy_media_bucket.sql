INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('eazy-media', 'eazy-media', false, 52428800,
  ARRAY['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/quicktime','audio/mpeg','audio/mp4','audio/wav'])
ON CONFLICT (id) DO NOTHING;