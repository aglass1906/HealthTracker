-- Allow one profile to belong to multiple communities while preserving the
-- existing families/family_id naming used by the app.

CREATE TABLE IF NOT EXISTS public.family_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  family_id uuid NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'member',
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (family_id, user_id)
);

CREATE INDEX IF NOT EXISTS family_memberships_family_id_idx
  ON public.family_memberships(family_id);

CREATE INDEX IF NOT EXISTS family_memberships_user_id_idx
  ON public.family_memberships(user_id);

INSERT INTO public.family_memberships (family_id, user_id, role)
SELECT family_id, id, 'member'
FROM public.profiles
WHERE family_id IS NOT NULL
ON CONFLICT (family_id, user_id) DO NOTHING;

ALTER TABLE public.family_memberships ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_family_member(check_family_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.family_memberships membership
    WHERE membership.family_id = check_family_id
      AND membership.user_id = (SELECT auth.uid())
  );
$$;

DROP POLICY IF EXISTS family_memberships_select ON public.family_memberships;
DROP POLICY IF EXISTS family_memberships_insert ON public.family_memberships;
DROP POLICY IF EXISTS family_memberships_delete ON public.family_memberships;

CREATE POLICY family_memberships_select ON public.family_memberships
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR public.is_family_member(family_id)
  );

CREATE POLICY family_memberships_insert ON public.family_memberships
  FOR INSERT TO authenticated
  WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY family_memberships_delete ON public.family_memberships
  FOR DELETE TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Keep community-scoped reads bound to explicit membership. Policy names use
-- IF EXISTS because early local databases may have different policy names.
DROP POLICY IF EXISTS families_select ON public.families;
CREATE POLICY families_select ON public.families
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS families_insert ON public.families;
CREATE POLICY families_insert ON public.families
  FOR INSERT TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS social_events_select ON public.social_events;
CREATE POLICY social_events_select ON public.social_events
  FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));

DROP POLICY IF EXISTS social_events_insert ON public.social_events;
CREATE POLICY social_events_insert ON public.social_events
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND public.is_family_member(family_id)
  );

DROP POLICY IF EXISTS challenges_select ON public.challenges;
CREATE POLICY challenges_select ON public.challenges
  FOR SELECT TO authenticated
  USING (public.is_family_member(family_id));

DROP POLICY IF EXISTS challenges_insert ON public.challenges;
CREATE POLICY challenges_insert ON public.challenges
  FOR INSERT TO authenticated
  WITH CHECK (
    creator_id = (SELECT auth.uid())
    AND public.is_family_member(family_id)
  );

DROP POLICY IF EXISTS daily_stats_select ON public.daily_stats;
CREATE POLICY daily_stats_select ON public.daily_stats
  FOR SELECT TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS (
      SELECT 1
      FROM public.family_memberships viewer_membership
      JOIN public.family_memberships subject_membership
        ON subject_membership.family_id = viewer_membership.family_id
      WHERE viewer_membership.user_id = (SELECT auth.uid())
        AND subject_membership.user_id = daily_stats.user_id
    )
  );
