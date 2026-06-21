ALTER TABLE public.nutrition_logs
  DROP CONSTRAINT IF EXISTS nutrition_logs_source_check;

ALTER TABLE public.nutrition_logs
  ADD CONSTRAINT nutrition_logs_source_check
  CHECK (source IN ('photo', 'barcode', 'manual', 'copy', 'ai_text'));
