-- Wrap auth.uid() in (select auth.uid()) so it is evaluated once per query
-- rather than once per row, per the RLS performance best practice.

-- nutrition_logs
DROP POLICY nutrition_logs_select ON public.nutrition_logs;
DROP POLICY nutrition_logs_insert ON public.nutrition_logs;
DROP POLICY nutrition_logs_update ON public.nutrition_logs;
DROP POLICY nutrition_logs_delete ON public.nutrition_logs;

CREATE POLICY nutrition_logs_select ON public.nutrition_logs
  FOR SELECT TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE POLICY nutrition_logs_insert ON public.nutrition_logs
  FOR INSERT TO authenticated WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY nutrition_logs_update ON public.nutrition_logs
  FOR UPDATE TO authenticated USING (user_id = (SELECT auth.uid()));

CREATE POLICY nutrition_logs_delete ON public.nutrition_logs
  FOR DELETE TO authenticated USING (user_id = (SELECT auth.uid()));

-- nutrition_log_items (EXISTS subquery also benefits from cached auth.uid())
DROP POLICY nutrition_log_items_select ON public.nutrition_log_items;
DROP POLICY nutrition_log_items_insert ON public.nutrition_log_items;
DROP POLICY nutrition_log_items_update ON public.nutrition_log_items;
DROP POLICY nutrition_log_items_delete ON public.nutrition_log_items;

CREATE POLICY nutrition_log_items_select ON public.nutrition_log_items
  FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = nutrition_log_items.log_id AND l.user_id = (SELECT auth.uid())
  ));

CREATE POLICY nutrition_log_items_insert ON public.nutrition_log_items
  FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = log_id AND l.user_id = (SELECT auth.uid())
  ));

CREATE POLICY nutrition_log_items_update ON public.nutrition_log_items
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = nutrition_log_items.log_id AND l.user_id = (SELECT auth.uid())
  ));

CREATE POLICY nutrition_log_items_delete ON public.nutrition_log_items
  FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.nutrition_logs l
    WHERE l.id = nutrition_log_items.log_id AND l.user_id = (SELECT auth.uid())
  ));
