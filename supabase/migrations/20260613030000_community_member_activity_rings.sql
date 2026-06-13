-- Include the latest activity ring values in community member summaries.

DROP FUNCTION IF EXISTS public.community_member_summary(uuid, uuid);

CREATE FUNCTION public.community_member_summary(
  community_id uuid,
  member_id uuid
)
RETURNS TABLE (
  stat_date date,
  steps integer,
  calories integer,
  distance double precision,
  exercise_minutes integer,
  workouts_count integer,
  move_ring_value double precision,
  exercise_ring_value double precision,
  stand_ring_value double precision,
  nutrition_date date,
  nutrition_calories double precision,
  protein_g double precision,
  carb_g double precision,
  fat_g double precision,
  last_update_at timestamptz,
  last_update_type text
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  WITH authorized AS (
    SELECT EXISTS (
      SELECT 1
      FROM public.family_memberships viewer
      JOIN public.family_memberships subject
        ON subject.family_id = viewer.family_id
      WHERE viewer.family_id = community_id
        AND viewer.user_id = (SELECT auth.uid())
        AND subject.user_id = member_id
    ) AS allowed
  ),
  latest_stat AS (
    SELECT
      stats.date,
      stats.steps,
      stats.calories,
      stats.distance,
      stats.exercise_minutes,
      stats.workouts_count,
      stats.move_ring_value,
      stats.exercise_ring_value,
      stats.stand_ring_value
    FROM public.daily_stats stats, authorized
    WHERE authorized.allowed
      AND stats.user_id = member_id
    ORDER BY stats.date DESC
    LIMIT 1
  ),
  latest_nutrition_day AS (
    SELECT logs.logged_at::date AS date
    FROM public.nutrition_logs logs, authorized
    WHERE authorized.allowed
      AND logs.user_id = member_id
      AND logs.status = 'confirmed'
    ORDER BY logs.logged_at DESC
    LIMIT 1
  ),
  nutrition_summary AS (
    SELECT
      day.date,
      COALESCE(SUM(items.calories), 0)::double precision AS calories,
      COALESCE(SUM(items.protein_g), 0)::double precision AS protein_g,
      COALESCE(SUM(items.carb_g), 0)::double precision AS carb_g,
      COALESCE(SUM(items.fat_g), 0)::double precision AS fat_g,
      MAX(logs.logged_at) AS updated_at
    FROM latest_nutrition_day day
    JOIN public.nutrition_logs logs
      ON logs.user_id = member_id
      AND logs.status = 'confirmed'
      AND logs.logged_at::date = day.date
    JOIN public.nutrition_log_items items ON items.log_id = logs.id
    GROUP BY day.date
  ),
  latest_event AS (
    SELECT events.created_at, events.type
    FROM public.social_events events, authorized
    WHERE authorized.allowed
      AND events.family_id = community_id
      AND events.user_id = member_id
    ORDER BY events.created_at DESC
    LIMIT 1
  ),
  latest_update AS (
    SELECT updated_at, type
    FROM (
      SELECT latest_event.created_at AS updated_at, latest_event.type
      FROM latest_event
      UNION ALL
      SELECT latest_stat.date::timestamptz, 'activity'
      FROM latest_stat
      UNION ALL
      SELECT nutrition_summary.updated_at, 'nutrition'
      FROM nutrition_summary
    ) updates
    ORDER BY updated_at DESC
    LIMIT 1
  )
  SELECT
    latest_stat.date,
    latest_stat.steps,
    latest_stat.calories,
    latest_stat.distance,
    latest_stat.exercise_minutes,
    latest_stat.workouts_count,
    latest_stat.move_ring_value,
    latest_stat.exercise_ring_value,
    latest_stat.stand_ring_value,
    nutrition_summary.date,
    nutrition_summary.calories,
    nutrition_summary.protein_g,
    nutrition_summary.carb_g,
    nutrition_summary.fat_g,
    latest_update.updated_at,
    latest_update.type
  FROM authorized
  LEFT JOIN latest_stat ON true
  LEFT JOIN nutrition_summary ON true
  LEFT JOIN latest_update ON true
  WHERE authorized.allowed;
$$;

REVOKE ALL ON FUNCTION public.community_member_summary(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.community_member_summary(uuid, uuid) TO authenticated;
