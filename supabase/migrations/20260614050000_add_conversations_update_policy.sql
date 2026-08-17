-- Allow participants to update conversations they are part of (e.g. theme_color)
DROP POLICY IF EXISTS "Participants can update conversations" ON public.conversations;
CREATE POLICY "Participants can update conversations"
  ON public.conversations
  FOR UPDATE
  USING (
    auth.uid() = participant1_id OR auth.uid() = participant2_id
  );

