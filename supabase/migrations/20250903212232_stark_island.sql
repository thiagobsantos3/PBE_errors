/*
  # Fix Team Members RLS Infinite Recursion

  1. Problem
    - Infinite recursion detected in policy for relation "team_members"
    - Circular dependencies between user_profiles and team_members policies

  2. Solution
    - Drop all existing policies on team_members table
    - Create minimal, non-recursive policies
    - Remove any cross-table references that could cause loops

  3. Security
    - Users can view their own team member entries
    - Admins can manage all team member data
    - Team owners can manage their team members (using direct team ownership check)
*/

-- Drop all existing policies on team_members to eliminate recursion
DROP POLICY IF EXISTS "admins_can_manage_team_members" ON team_members;
DROP POLICY IF EXISTS "team_members_can_view_teammates_entries" ON team_members;
DROP POLICY IF EXISTS "users_can_view_own_team_member_entry" ON team_members;

-- Create minimal, non-recursive policies for team_members
CREATE POLICY "team_members_select_own"
  ON team_members
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "team_members_insert_own"
  ON team_members
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "team_members_update_own"
  ON team_members
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "team_members_delete_own"
  ON team_members
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Admin policy for team_members (checking role directly from auth.jwt())
CREATE POLICY "team_members_admin_all"
  ON team_members
  FOR ALL
  TO authenticated
  USING (
    COALESCE((auth.jwt() ->> 'user_metadata' ->> 'role'), 'user') = 'admin'
  )
  WITH CHECK (
    COALESCE((auth.jwt() ->> 'user_metadata' ->> 'role'), 'user') = 'admin'
  );

-- Team owner policy for team_members (direct ownership check without joins)
CREATE POLICY "team_members_team_owner_manage"
  ON team_members
  FOR ALL
  TO authenticated
  USING (
    team_id IN (
      SELECT id FROM teams WHERE owner_id = auth.uid()
    )
  )
  WITH CHECK (
    team_id IN (
      SELECT id FROM teams WHERE owner_id = auth.uid()
    )
  );

-- Also simplify user_profiles policies to avoid any potential recursion
DROP POLICY IF EXISTS "user_profiles_select_teammates" ON user_profiles;
DROP POLICY IF EXISTS "team_members_can_view_teammates_profiles" ON user_profiles;

-- Create a simple policy for team members to view each other's profiles
CREATE POLICY "user_profiles_select_teammates_simple"
  ON user_profiles
  FOR SELECT
  TO authenticated
  USING (
    team_id IS NOT NULL AND 
    team_id IN (
      SELECT team_id FROM user_profiles WHERE id = auth.uid()
    )
  );