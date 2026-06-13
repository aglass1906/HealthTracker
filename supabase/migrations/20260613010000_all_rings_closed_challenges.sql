ALTER TABLE public.daily_stats
    ADD COLUMN IF NOT EXISTS all_rings_closed INTEGER NOT NULL DEFAULT 0
    CHECK (all_rings_closed IN (0, 1));

ALTER TABLE public.challenges
    DROP CONSTRAINT IF EXISTS challenges_metric_check;

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
            'stand_ring',
            'all_rings_closed'
        )
    );
