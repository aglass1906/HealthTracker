ALTER TABLE public.nutrition_log_items
  ADD COLUMN IF NOT EXISTS image_url TEXT;
