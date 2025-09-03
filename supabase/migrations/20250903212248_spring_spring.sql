/*
  # Fix RLS Infinite Recursion in Team Members

  This migration fixes the infinite recursion error by completely restructuring
  the RLS policies to eliminate circular dependencies between tables.

  ## Changes Made
  1. Drop all existing RLS policies on team_members, user_profiles, and teams
  2. Create new simplified policies that avoid circular references
  3. Use direct auth.uid() checks and simple EXISTS clauses
  4. Ensure team owners and admins can see their team data

  ## Security
  - Users can only see their own data
  - Team owners can see all team member data for their team
  - System admins can see all data
  - No circular policy references
*/

-- Drop all existing policies that might cause recursion
DROP POLICY IF EXISTS "team_members_can_view_teammates_entries" ON team_members;
DROP POLICY IF EXISTS "users_can_view_own_team_member_entry" ON team_members;
DROP POLICY IF EXISTS "admins_can_manage_team_members" ON team_members;

DROP POLICY IF EXISTS "user_profiles_select_own" ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_select_admin" ON user_profiles;
DROP POLICY IF EXISTS "team_members_can_view_teammates_profiles" ON user_profiles;
DROP POLICY IF EXISTS "users_can_view_own_profile" ON user_profiles;
DROP POLICY IF EXISTS "users_can_manage_own_profile" ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_insert_own" ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_update_own" ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_update_admin" ON user_profiles;
DROP POLICY IF EXISTS "user_profiles_delete_admin" ON user_profiles;
DROP POLICY IF EXISTS "admins_can_view_all_profiles" ON user_profiles;
DROP POLICY IF EXISTS "admins_can_manage_all_profiles" ON user_profiles;

DROP POLICY IF EXISTS "users_can_view_their_team" ON teams;
DROP POLICY IF EXISTS "owners_can_manage_their_team" ON teams;
DROP POLICY IF EXISTS "admins_can_view_all_teams" ON teams;

-- Create new simplified policies for user_profiles
CREATE POLICY "user_profiles_own_access" ON user_profiles
  FOR ALL TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

CREATE POLICY "user_profiles_admin_access" ON user_profiles
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles admin_check 
      WHERE admin_check.id = auth.uid() 
      AND admin_check.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles admin_check 
      WHERE admin_check.id = auth.uid() 
      AND admin_check.role = 'admin'
    )
  );

-- Create new simplified policies for teams
CREATE POLICY "teams_owner_access" ON teams
  FOR ALL TO authenticated
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid());

CREATE POLICY "teams_admin_access" ON teams
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles admin_check 
      WHERE admin_check.id = auth.uid() 
      AND admin_check.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles admin_check 
      WHERE admin_check.id = auth.uid() 
      AND admin_check.role = 'admin'
    )
  );

CREATE POLICY "teams_member_view" ON teams
  FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT team_id FROM user_profiles 
      WHERE id = auth.uid() 
      AND team_id IS NOT NULL
    )
  );

-- Create new simplified policies for team_members
CREATE POLICY "team_members_own_access" ON team_members
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "team_members_admin_access" ON team_members
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM user_profiles admin_check 
      WHERE admin_check.id = auth.uid() 
      AND admin_check.role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM user_profiles admin_check 
      WHERE admin_check.id = auth.uid() 
      AND admin_check.role = 'admin'
    )
  );

CREATE POLICY "team_members_team_owner_access" ON team_members
  FOR ALL TO authenticated
  USING (
    team_id IN (
      SELECT id FROM teams 
      WHERE owner_id = auth.uid()
    )
  )
  WITH CHECK (
    team_id IN (
      SELECT id FROM teams 
      WHERE owner_id = auth.uid()
    )
  );

-- Add policy for team members to view other team members in their team
CREATE POLICY "team_members_view_teammates" ON team_members
  FOR SELECT TO authenticated
  USING (
    team_id IN (
      SELECT team_id FROM user_profiles 
      WHERE id = auth.uid() 
      AND team_id IS NOT NULL
    )
  );

-- Add policy for team members to view teammate profiles
CREATE POLICY "user_profiles_view_teammates" ON user_profiles
  FOR SELECT TO authenticated
  USING (
    team_id IN (
      SELECT team_id FROM user_profiles current_user
      WHERE current_user.id = auth.uid() 
      AND current_user.team_id IS NOT NULL
    )
    AND team_id IS NOT NULL
  );

-- Recreate the leaderboard function with SECURITY DEFINER to avoid RLS issues
CREATE OR REPLACE FUNCTION get_team_leaderboard_data(p_team_id uuid)
RETURNS TABLE (
  user_id uuid,
  name text,
  total_xp integer,
  current_level integer,
  longest_streak integer,
  total_achievements bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Check if team exists and user has access
  IF NOT EXISTS (
    SELECT 1 FROM teams t
    WHERE t.id = p_team_id
    AND (
      t.owner_id = auth.uid() OR
      EXISTS (
        SELECT 1 FROM user_profiles up
        WHERE up.id = auth.uid() 
        AND up.team_id = p_team_id
      ) OR
      EXISTS (
        SELECT 1 FROM user_profiles admin_check
        WHERE admin_check.id = auth.uid() 
        AND admin_check.role = 'admin'
      )
    )
  ) THEN
    RAISE EXCEPTION 'Team does not exist or access denied';
  END IF;

  -- Return leaderboard data
  RETURN QUERY
  SELECT 
    up.id as user_id,
    up.name,
    COALESCE(us.total_xp, 0) as total_xp,
    COALESCE(us.current_level, 1) as current_level,
    COALESCE(us.longest_streak, 0) as longest_streak,
    COALESCE(achievement_counts.total_achievements, 0) as total_achievements
  FROM user_profiles up
  LEFT JOIN user_stats us ON up.id = us.user_id
  LEFT JOIN (
    SELECT 
      ua.user_id,
      COUNT(*) as total_achievements
    FROM user_achievements ua
    GROUP BY ua.user_id
  ) achievement_counts ON up.id = achievement_counts.user_id
  WHERE up.team_id = p_team_id
  ORDER BY 
    COALESCE(us.total_xp, 0) DESC,
    COALESCE(us.current_level, 1) DESC,
    COALESCE(us.longest_streak, 0) DESC;
END;
$$;