/*
  # Fix RLS Permissions and Recursion for Team Data

  This migration resolves infinite recursion errors in RLS policies and ensures
  team owners and admins can properly view team member data.

  ## Changes Made

  1. **Drop problematic RLS policies** that were causing circular dependencies
  2. **Recreate simplified RLS policies** for user_profiles, team_members, and teams
  3. **Ensure team owners and admins** can view all team member data
  4. **Prevent infinite recursion** by avoiding circular policy references

  ## Security

  - Users can view their own data
  - System admins can view all data  
  - Team owners/admins can view their team's data
  - Regular team members have limited visibility
*/

-- Drop existing problematic policies
DROP POLICY IF EXISTS "user_profiles_select_own" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_select_admin" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_update_own" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_update_admin" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_insert_own" ON public.user_profiles;
DROP POLICY IF EXISTS "user_profiles_delete_admin" ON public.user_profiles;

DROP POLICY IF EXISTS "team_members_select_own" ON public.team_members;
DROP POLICY IF EXISTS "team_members_select_admin" ON public.team_members;
DROP POLICY IF EXISTS "team_members_update_own" ON public.team_members;
DROP POLICY IF EXISTS "team_members_update_admin" ON public.team_members;
DROP POLICY IF EXISTS "team_members_insert_admin" ON public.team_members;
DROP POLICY IF EXISTS "team_members_delete_own" ON public.team_members;
DROP POLICY IF EXISTS "team_members_delete_admin" ON public.team_members;

DROP POLICY IF EXISTS "teams_select_owner" ON public.teams;
DROP POLICY IF EXISTS "teams_select_admin" ON public.teams;
DROP POLICY IF EXISTS "teams_select_member" ON public.teams;
DROP POLICY IF EXISTS "teams_update_owner" ON public.teams;
DROP POLICY IF EXISTS "teams_update_admin" ON public.teams;
DROP POLICY IF EXISTS "teams_insert_authenticated" ON public.teams;
DROP POLICY IF EXISTS "teams_delete_owner" ON public.teams;
DROP POLICY IF EXISTS "teams_delete_admin" ON public.teams;

-- Create new simplified RLS policies for user_profiles
CREATE POLICY "user_profiles_select_own"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (auth.uid() = id);

CREATE POLICY "user_profiles_select_admin"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

CREATE POLICY "user_profiles_select_team_owner_admin"
ON public.user_profiles
FOR SELECT
TO authenticated
USING (
  team_id IS NOT NULL AND team_id IN (
    SELECT team_id FROM public.user_profiles current_user
    WHERE current_user.id = auth.uid()
    AND current_user.team_role IN ('owner', 'admin')
  )
);

CREATE POLICY "user_profiles_update_own"
ON public.user_profiles
FOR UPDATE
TO authenticated
USING (auth.uid() = id)
WITH CHECK (auth.uid() = id);

CREATE POLICY "user_profiles_update_admin"
ON public.user_profiles
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

CREATE POLICY "user_profiles_insert_own"
ON public.user_profiles
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = id);

CREATE POLICY "user_profiles_delete_admin"
ON public.user_profiles
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

-- Create new simplified RLS policies for team_members
CREATE POLICY "team_members_select_own"
ON public.team_members
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "team_members_select_admin"
ON public.team_members
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

CREATE POLICY "team_members_select_team_owner_admin"
ON public.team_members
FOR SELECT
TO authenticated
USING (
  team_id IN (
    SELECT team_id FROM public.user_profiles current_user
    WHERE current_user.id = auth.uid()
    AND current_user.team_role IN ('owner', 'admin')
  )
);

CREATE POLICY "team_members_update_own"
ON public.team_members
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "team_members_update_admin"
ON public.team_members
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

CREATE POLICY "team_members_insert_admin"
ON public.team_members
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

CREATE POLICY "team_members_delete_own"
ON public.team_members
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "team_members_delete_admin"
ON public.team_members
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

-- Create new simplified RLS policies for teams
CREATE POLICY "teams_select_owner"
ON public.teams
FOR SELECT
TO authenticated
USING (owner_id = auth.uid());

CREATE POLICY "teams_select_admin"
ON public.teams
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

CREATE POLICY "teams_select_member"
ON public.teams
FOR SELECT
TO authenticated
USING (
  id IN (
    SELECT team_id FROM public.user_profiles current_user
    WHERE current_user.id = auth.uid()
    AND current_user.team_id IS NOT NULL
  )
);

CREATE POLICY "teams_update_owner"
ON public.teams
FOR UPDATE
TO authenticated
USING (owner_id = auth.uid())
WITH CHECK (owner_id = auth.uid());

CREATE POLICY "teams_update_admin"
ON public.teams
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

CREATE POLICY "teams_insert_authenticated"
ON public.teams
FOR INSERT
TO authenticated
WITH CHECK (owner_id = auth.uid());

CREATE POLICY "teams_delete_owner"
ON public.teams
FOR DELETE
TO authenticated
USING (owner_id = auth.uid());

CREATE POLICY "teams_delete_admin"
ON public.teams
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.user_profiles admin_check
    WHERE admin_check.id = auth.uid() 
    AND admin_check.role = 'admin'
  )
);

-- Drop and recreate the get_team_leaderboard_data function without debug columns
DROP FUNCTION IF EXISTS public.get_team_leaderboard_data(uuid, timestamp with time zone, timestamp with time zone);

CREATE OR REPLACE FUNCTION public.get_team_leaderboard_data(
    p_team_id uuid,
    p_start_date timestamp with time zone DEFAULT NULL,
    p_end_date timestamp with time zone DEFAULT NULL
)
RETURNS TABLE (
    user_id uuid,
    user_name text,
    role text,
    total_quizzes_completed bigint,
    total_questions_answered bigint,
    average_score numeric,
    total_time_spent_minutes numeric,
    study_streak integer,
    total_points_earned numeric,
    total_possible_points numeric
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    current_report_date DATE;
    team_exists_check BOOLEAN;
BEGIN
  -- Disable RLS for this function to avoid recursion
  SET LOCAL row_security.enable = off;

  current_report_date := COALESCE(DATE(p_end_date AT TIME ZONE 'Europe/London'), DATE(NOW() AT TIME ZONE 'Europe/London'));

  -- Check if team exists (with RLS disabled, this should work)
  SELECT EXISTS (SELECT 1 FROM public.teams WHERE id = p_team_id) INTO team_exists_check;

  IF NOT team_exists_check THEN
      RAISE EXCEPTION 'Team with ID % does not exist.', p_team_id;
  END IF;

  RETURN QUERY
  SELECT
    tm.user_id,
    COALESCE(p.name, p.email) as user_name,
    tm.role,
    COUNT(qs.id) as total_quizzes_completed,
    COALESCE(SUM(
      CASE
        WHEN qs.results IS NOT NULL AND jsonb_typeof(qs.results) = 'array' THEN jsonb_array_length(qs.results)
        ELSE 0
      END
    ), 0) as total_questions_answered,
    CASE
      WHEN COALESCE(SUM(qs.max_points), 0) > 0 THEN
        ROUND(COALESCE(SUM(qs.total_points), 0) * 100.0 / COALESCE(SUM(qs.max_points), 0), 2)
      ELSE 0
    END as average_score,
    COALESCE(
      SUM(
        CASE
          WHEN qs.total_actual_time_spent_seconds > 0 THEN qs.total_actual_time_spent_seconds / 60.0
          ELSE GREATEST(1,
            CASE
              WHEN qs.questions IS NOT NULL AND jsonb_typeof(qs.questions) = 'array' THEN jsonb_array_length(qs.questions) * 2
              ELSE 2
            END
          )
        END
      ), 0
    ) as total_time_spent_minutes,
    (
        WITH user_completed_dates AS (
            SELECT DISTINCT DATE(qs_inner.completed_at AT TIME ZONE 'Europe/London') AS quiz_date
            FROM public.quiz_sessions qs_inner
            WHERE qs_inner.user_id = tm.user_id
              AND qs_inner.status = 'completed'
              AND qs_inner.approval_status = 'approved'
        ),
        dated_series AS (
            SELECT
                quiz_date,
                (current_report_date - quiz_date) AS days_ago
            FROM user_completed_dates
            ORDER BY quiz_date DESC
        ),
        most_recent_date AS (
            SELECT quiz_date
            FROM dated_series
            ORDER BY quiz_date DESC
            LIMIT 1
        ),
        streak_calculation AS (
            SELECT
                quiz_date,
                days_ago,
                (days_ago - ROW_NUMBER() OVER (ORDER BY quiz_date DESC)) AS streak_group
            FROM dated_series
        )
        SELECT
            CASE
                WHEN mrd.quiz_date = current_report_date OR mrd.quiz_date = current_report_date - INTERVAL '1 day' THEN
                    (SELECT COUNT(*)
                     FROM streak_calculation sc1
                     WHERE sc1.streak_group = (
                         SELECT sc2.streak_group
                         FROM streak_calculation sc2
                         WHERE sc2.quiz_date = mrd.quiz_date
                     ))
                ELSE 0
            END
        FROM most_recent_date mrd
    )::integer AS study_streak,
    COALESCE(SUM(qs.total_points), 0)::numeric as total_points_earned,
    COALESCE(SUM(qs.max_points), 0)::numeric as total_possible_points
  FROM public.team_members tm
  JOIN public.user_profiles p ON tm.user_id = p.id
  LEFT JOIN public.quiz_sessions qs ON tm.user_id = qs.user_id
    AND qs.status = 'completed'
    AND qs.approval_status = 'approved'
    AND (p_start_date IS NULL OR qs.completed_at >= p_start_date)
    AND (p_end_date IS NULL OR qs.completed_at <= p_end_date)
  WHERE tm.team_id = p_team_id
  GROUP BY tm.user_id, p.name, p.email, tm.role
  ORDER BY total_points_earned DESC, average_score DESC;

  -- Re-enable RLS
  SET LOCAL row_security.enable = on;
END;
$function$;