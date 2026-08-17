-- Fix user_push_tokens RLS policies to allow users to register/upsert tokens even if they were previously associated with another user account (token re-assignment on shared devices).

DROP POLICY IF EXISTS "Users can manage their own tokens" ON public.user_push_tokens;
DROP POLICY IF EXISTS "Users can select their own tokens" ON public.user_push_tokens;
DROP POLICY IF EXISTS "Users can insert their own tokens" ON public.user_push_tokens;
DROP POLICY IF EXISTS "Users can update tokens to their own user_id" ON public.user_push_tokens;
DROP POLICY IF EXISTS "Users can delete their own tokens" ON public.user_push_tokens;

CREATE POLICY "Users can select their own tokens"
  ON public.user_push_tokens FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own tokens"
  ON public.user_push_tokens FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- USING (true) allows the update to target any row by token,
-- but WITH CHECK ensures they can only save it if they set the user_id to their own ID.
CREATE POLICY "Users can update tokens to their own user_id"
  ON public.user_push_tokens FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own tokens"
  ON public.user_push_tokens FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
