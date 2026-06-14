CREATE TABLE IF NOT EXISTS public.challenge_metrics (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id uuid NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  metric text NOT NULL,
  display_order integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (challenge_id, metric),
  UNIQUE (challenge_id, display_order),
  CONSTRAINT challenge_metrics_metric_check CHECK (
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
  )
);

INSERT INTO public.challenge_metrics (challenge_id, metric, display_order)
SELECT id, metric, 0
FROM public.challenges
ON CONFLICT (challenge_id, metric) DO NOTHING;

ALTER TABLE public.challenges
  ADD COLUMN IF NOT EXISTS finalized_at timestamptz;

ALTER TABLE public.challenge_rounds
  ADD COLUMN IF NOT EXISTS finalized_at timestamptz;

CREATE TABLE IF NOT EXISTS public.challenge_metric_winners (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  challenge_id uuid NOT NULL REFERENCES public.challenges(id) ON DELETE CASCADE,
  round_id uuid REFERENCES public.challenge_rounds(id) ON DELETE CASCADE,
  metric text NOT NULL,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  value double precision NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT challenge_metric_winners_metric_check CHECK (
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
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS challenge_metric_winners_challenge_unique
  ON public.challenge_metric_winners(challenge_id, metric, user_id)
  WHERE round_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS challenge_metric_winners_round_unique
  ON public.challenge_metric_winners(round_id, metric, user_id)
  WHERE round_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS challenge_metrics_challenge_id_idx
  ON public.challenge_metrics(challenge_id);

CREATE INDEX IF NOT EXISTS challenge_metric_winners_challenge_id_idx
  ON public.challenge_metric_winners(challenge_id);

CREATE INDEX IF NOT EXISTS challenge_metric_winners_round_id_idx
  ON public.challenge_metric_winners(round_id);

ALTER TABLE public.challenge_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_metric_winners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.challenge_rounds ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS challenge_metrics_select ON public.challenge_metrics;
CREATE POLICY challenge_metrics_select ON public.challenge_metrics
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_metrics.challenge_id
        AND public.is_family_member(challenge.family_id)
    )
  );

DROP POLICY IF EXISTS challenge_metrics_insert ON public.challenge_metrics;
CREATE POLICY challenge_metrics_insert ON public.challenge_metrics
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_metrics.challenge_id
        AND challenge.creator_id = (SELECT auth.uid())
        AND public.is_family_member(challenge.family_id)
    )
  );

DROP POLICY IF EXISTS challenge_metrics_delete ON public.challenge_metrics;
CREATE POLICY challenge_metrics_delete ON public.challenge_metrics
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_metrics.challenge_id
        AND challenge.creator_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS challenge_metric_winners_select ON public.challenge_metric_winners;
CREATE POLICY challenge_metric_winners_select ON public.challenge_metric_winners
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_metric_winners.challenge_id
        AND public.is_family_member(challenge.family_id)
    )
  );

DROP POLICY IF EXISTS challenge_metric_winners_insert ON public.challenge_metric_winners;
CREATE POLICY challenge_metric_winners_insert ON public.challenge_metric_winners
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_metric_winners.challenge_id
        AND public.is_family_member(challenge.family_id)
    )
  );

DROP POLICY IF EXISTS challenges_update ON public.challenges;
CREATE POLICY challenges_update ON public.challenges
  FOR UPDATE TO authenticated
  USING (public.is_family_member(family_id))
  WITH CHECK (public.is_family_member(family_id));

DROP POLICY IF EXISTS challenges_delete ON public.challenges;
CREATE POLICY challenges_delete ON public.challenges
  FOR DELETE TO authenticated
  USING (creator_id = (SELECT auth.uid()));

DROP POLICY IF EXISTS challenge_rounds_select ON public.challenge_rounds;
CREATE POLICY challenge_rounds_select ON public.challenge_rounds
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_rounds.challenge_id
        AND public.is_family_member(challenge.family_id)
    )
  );

DROP POLICY IF EXISTS challenge_rounds_insert ON public.challenge_rounds;
CREATE POLICY challenge_rounds_insert ON public.challenge_rounds
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_rounds.challenge_id
        AND challenge.creator_id = (SELECT auth.uid())
    )
  );

DROP POLICY IF EXISTS challenge_rounds_update ON public.challenge_rounds;
CREATE POLICY challenge_rounds_update ON public.challenge_rounds
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.challenges challenge
      WHERE challenge.id = challenge_rounds.challenge_id
        AND public.is_family_member(challenge.family_id)
    )
  );
