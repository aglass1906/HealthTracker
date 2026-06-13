ALTER TABLE public.daily_stats
    ADD COLUMN IF NOT EXISTS move_ring_value DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS exercise_ring_value DOUBLE PRECISION NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS stand_ring_value DOUBLE PRECISION NOT NULL DEFAULT 0;

-- Replace any existing metric check so new ring metrics can be inserted.
DO $$
DECLARE
    constraint_record RECORD;
BEGIN
    FOR constraint_record IN
        SELECT conname
        FROM pg_constraint
        WHERE conrelid = 'public.challenges'::regclass
          AND contype = 'c'
          AND pg_get_constraintdef(oid) LIKE '%metric%'
    LOOP
        EXECUTE format(
            'ALTER TABLE public.challenges DROP CONSTRAINT %I',
            constraint_record.conname
        );
    END LOOP;
END
$$;

ALTER TABLE public.challenges
    ADD CONSTRAINT challenges_metric_check
    CHECK (
        metric IN (
            'steps',
            'calories',
            'distance',
            'exercise_minutes',
            'flights',
            'workouts',
            'move_ring',
            'exercise_ring',
            'stand_ring'
        )
    );
