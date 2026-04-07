-- Nutrition logging: logs, line items, RLS, and private meal photo storage.

CREATE TABLE public.nutrition_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  logged_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  meal_type TEXT,
  source TEXT NOT NULL CHECK (source IN ('photo', 'barcode', 'manual')),
  barcode_raw TEXT,
  photo_path TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.nutrition_log_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  log_id UUID NOT NULL REFERENCES public.nutrition_logs (id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  brand TEXT,
  serving_amount DOUBLE PRECISION NOT NULL DEFAULT 1,
  serving_unit TEXT NOT NULL DEFAULT 'serving',
  grams DOUBLE PRECISION,
  calories DOUBLE PRECISION NOT NULL DEFAULT 0,
  protein_g DOUBLE PRECISION NOT NULL DEFAULT 0,
  carb_g DOUBLE PRECISION NOT NULL DEFAULT 0,
  fat_g DOUBLE PRECISION NOT NULL DEFAULT 0,
  fiber_g DOUBLE PRECISION,
  sodium_mg DOUBLE PRECISION,
  fdc_id BIGINT,
  external_product_id TEXT,
  nutrients JSONB
);

CREATE INDEX nutrition_logs_user_logged_idx ON public.nutrition_logs (user_id, logged_at DESC);
CREATE INDEX nutrition_log_items_log_idx ON public.nutrition_log_items (log_id);

ALTER TABLE public.nutrition_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nutrition_log_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY nutrition_logs_select ON public.nutrition_logs
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY nutrition_logs_insert ON public.nutrition_logs
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY nutrition_logs_update ON public.nutrition_logs
  FOR UPDATE TO authenticated USING (user_id = auth.uid());

CREATE POLICY nutrition_logs_delete ON public.nutrition_logs
  FOR DELETE TO authenticated USING (user_id = auth.uid());

CREATE POLICY nutrition_log_items_select ON public.nutrition_log_items
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = nutrition_log_items.log_id AND l.user_id = auth.uid()
  ));

CREATE POLICY nutrition_log_items_insert ON public.nutrition_log_items
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = log_id AND l.user_id = auth.uid()
  ));

CREATE POLICY nutrition_log_items_update ON public.nutrition_log_items
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = nutrition_log_items.log_id AND l.user_id = auth.uid()
  ));

CREATE POLICY nutrition_log_items_delete ON public.nutrition_log_items
  FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = nutrition_log_items.log_id AND l.user_id = auth.uid()
  ));

INSERT INTO storage.buckets (id, name, public)
VALUES ('meal-photos', 'meal-photos', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY meal_photos_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'meal-photos'
    AND (storage.foldername (name))[1] = auth.uid()::text
  );

CREATE POLICY meal_photos_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'meal-photos'
    AND (storage.foldername (name))[1] = auth.uid()::text
  );

CREATE POLICY meal_photos_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'meal-photos'
    AND (storage.foldername (name))[1] = auth.uid()::text
  );

CREATE POLICY meal_photos_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'meal-photos'
    AND (storage.foldername (name))[1] = auth.uid()::text
  );
