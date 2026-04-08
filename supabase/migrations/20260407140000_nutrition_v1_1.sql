-- V1.1: meal notes, per-line quantity, no RLS changes.

ALTER TABLE public.nutrition_logs
  ADD COLUMN IF NOT EXISTS notes TEXT;

ALTER TABLE public.nutrition_log_items
  ADD COLUMN IF NOT EXISTS quantity DOUBLE PRECISION NOT NULL DEFAULT 1;

COMMENT ON COLUMN public.nutrition_log_items.quantity IS 'How many label servings (e.g. 2 pancakes); macros/grams stored are totals for the line.';
