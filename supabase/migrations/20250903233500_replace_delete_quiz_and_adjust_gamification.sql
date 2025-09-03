-- Replace RPC to safely delete a quiz and recalculate gamification without duplicate achievements

CREATE OR REPLACE FUNCTION public.delete_quiz_and_adjust_gamification(
  p_quiz_session_id uuid,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_response jsonb := jsonb_build_object('success', false);
  v_total_xp bigint := 0;
  v_current_level int := 1;
  v_longest_streak int := 0;
BEGIN
  -- Ensure only the owner can delete their session
  IF NOT EXISTS (
    SELECT 1 FROM public.quiz_sessions WHERE id = p_quiz_session_id AND user_id = p_user_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Quiz session not found or not owned by user');
  END IF;

  -- Delete the quiz session
  DELETE FROM public.quiz_sessions WHERE id = p_quiz_session_id;

  -- Recalculate total xp from remaining completed sessions; include bonus_xp
  SELECT COALESCE(SUM(total_points + COALESCE(bonus_xp, 0)), 0)
    INTO v_total_xp
  FROM public.quiz_sessions
  WHERE user_id = p_user_id AND status = 'completed';

  -- Recalculate longest streak from remaining completed sessions
  WITH daily AS (
    SELECT DISTINCT DATE(completed_at) AS d
    FROM public.quiz_sessions
    WHERE user_id = p_user_id AND status = 'completed' AND completed_at IS NOT NULL
  ), numbered AS (
    SELECT d,
           ROW_NUMBER() OVER (ORDER BY d) AS rn
    FROM daily
  ), grouped AS (
    SELECT d, rn, d - (rn || ' days')::interval AS grp
    FROM numbered
  )
  SELECT COALESCE(MAX(cnt), 0) INTO v_longest_streak
  FROM (
    SELECT COUNT(*) AS cnt
    FROM grouped
    GROUP BY grp
  ) s;

  -- Simple level calc: 100 XP per level (adjust if you have a function)
  v_current_level := GREATEST(1, FLOOR(v_total_xp / 100)::int);

  -- Upsert user_stats only; DO NOT touch user_achievements here to avoid duplicates
  INSERT INTO public.user_stats (user_id, total_xp, current_level, longest_streak, last_quiz_date)
  VALUES (p_user_id, v_total_xp, v_current_level, v_longest_streak, COALESCE((SELECT MAX(DATE(completed_at)) FROM public.quiz_sessions WHERE user_id = p_user_id AND status = 'completed'), CURRENT_DATE))
  ON CONFLICT (user_id) DO UPDATE SET
    total_xp = EXCLUDED.total_xp,
    current_level = EXCLUDED.current_level,
    longest_streak = EXCLUDED.longest_streak,
    last_quiz_date = EXCLUDED.last_quiz_date;

  v_response := jsonb_build_object('success', true);
  RETURN v_response;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_quiz_and_adjust_gamification(uuid, uuid) TO authenticated;

