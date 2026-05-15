-- Nutrition goals: per-user active goal targets for dashboard and nutrition progress.

CREATE TABLE IF NOT EXISTS public.nutrition_goals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  goal_type TEXT NOT NULL CHECK (goal_type IN ('low_carb', 'mediterranean', 'balanced', 'custom')),
  daily_calories DOUBLE PRECISION NOT NULL DEFAULT 2000 CHECK (daily_calories >= 0),
  protein_g DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (protein_g >= 0),
  carb_g DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (carb_g >= 0),
  fat_g DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (fat_g >= 0),
  sugar_g DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (sugar_g >= 0),
  sodium_mg DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (sodium_mg >= 0),
  fiber_g DOUBLE PRECISION CHECK (fiber_g IS NULL OR fiber_g >= 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS nutrition_goals_user_idx
  ON public.nutrition_goals (user_id, created_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS nutrition_goals_one_active_idx
  ON public.nutrition_goals (user_id)
  WHERE is_active;

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_nutrition_goals_updated_at ON public.nutrition_goals;
CREATE TRIGGER set_nutrition_goals_updated_at
  BEFORE UPDATE ON public.nutrition_goals
  FOR EACH ROW
  EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.nutrition_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY nutrition_goals_select ON public.nutrition_goals
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY nutrition_goals_insert ON public.nutrition_goals
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY nutrition_goals_update ON public.nutrition_goals
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY nutrition_goals_delete ON public.nutrition_goals
  FOR DELETE TO authenticated USING (user_id = auth.uid());
