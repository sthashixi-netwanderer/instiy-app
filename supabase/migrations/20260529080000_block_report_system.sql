-- ============================================================
-- Block & Report System
-- ============================================================

-- 1. BLOCKED USERS TABLE
CREATE TABLE IF NOT EXISTS public.blocked_users (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  blocker_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  blocked_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(blocker_id, blocked_id),
  CHECK (blocker_id != blocked_id)
);

CREATE INDEX idx_blocked_users_blocker ON public.blocked_users(blocker_id);
CREATE INDEX idx_blocked_users_blocked ON public.blocked_users(blocked_id);

ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;

-- Users can see who they've blocked
CREATE POLICY "Users can view own blocks"
  ON public.blocked_users FOR SELECT
  TO authenticated
  USING (blocker_id = auth.uid());

-- Users can block others
CREATE POLICY "Users can insert blocks"
  ON public.blocked_users FOR INSERT
  TO authenticated
  WITH CHECK (blocker_id = auth.uid());

-- Users can unblock
CREATE POLICY "Users can delete own blocks"
  ON public.blocked_users FOR DELETE
  TO authenticated
  USING (blocker_id = auth.uid());

-- Admin read access
CREATE POLICY "Admins can view all blocks"
  ON public.blocked_users FOR SELECT
  TO authenticated
  USING (public.is_admin(auth.uid()));


-- 2. REPORTS TABLE
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  reporter_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reported_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  category TEXT NOT NULL CHECK (category IN (
    'spam', 'harassment', 'scam', 'inappropriate_content',
    'fake_account', 'hate_speech', 'violence', 'illegal_activity', 'other'
  )),
  description TEXT,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'reviewed', 'resolved', 'dismissed')),
  admin_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  CHECK (reporter_id != reported_user_id)
);

CREATE INDEX idx_reports_reporter ON public.reports(reporter_id);
CREATE INDEX idx_reports_reported ON public.reports(reported_user_id);
CREATE INDEX idx_reports_status ON public.reports(status);
CREATE INDEX idx_reports_created ON public.reports(created_at DESC);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

-- Users can view their own reports (as reporter)
CREATE POLICY "Users can view own reports"
  ON public.reports FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid());

-- Users can create reports
CREATE POLICY "Users can insert reports"
  ON public.reports FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- Admin full access to reports
CREATE POLICY "Admins can view all reports"
  ON public.reports FOR SELECT
  TO authenticated
  USING (public.is_admin(auth.uid()));

CREATE POLICY "Admins can update reports"
  ON public.reports FOR UPDATE
  TO authenticated
  USING (public.is_admin(auth.uid()));

-- Auto-update updated_at
CREATE TRIGGER set_reports_updated_at
  BEFORE UPDATE ON public.reports
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- 3. BLOCK CHECK: Prevent messages to blocked users
-- Modify the handle_new_message trigger to check blocks
CREATE OR REPLACE FUNCTION public.handle_new_message()
RETURNS TRIGGER AS $$
DECLARE
  _receiver_id UUID;
  _sender_name TEXT;
  _is_blocked BOOLEAN;
BEGIN
  -- Find the other participant
  SELECT CASE
    WHEN c.participant1_id = NEW.sender_id THEN c.participant2_id
    ELSE c.participant1_id
  END INTO _receiver_id
  FROM public.conversations c
  WHERE c.id = NEW.conversation_id;

  -- Check if receiver has blocked the sender
  SELECT EXISTS(
    SELECT 1 FROM public.blocked_users
    WHERE blocker_id = _receiver_id AND blocked_id = NEW.sender_id
  ) INTO _is_blocked;

  -- If blocked, silently prevent the message
  IF _is_blocked THEN
    RETURN NULL;
  END IF;

  NEW.receiver_id := _receiver_id;

  -- Get sender name for notification
  SELECT COALESCE(u.full_name, 'Someone') INTO _sender_name
  FROM public.users u WHERE u.id = NEW.sender_id;

  -- Create notification
  INSERT INTO public.notifications (user_id, type, title, message, data)
  VALUES (
    _receiver_id,
    'new_message',
    _sender_name,
    CASE
      WHEN NEW.content IS NOT NULL AND NEW.content != '' THEN NEW.content
      WHEN NEW.media_type = 'video' THEN 'Sent a video'
      WHEN NEW.media_type = 'image' THEN 'Sent a photo'
      ELSE 'Sent a message'
    END,
    jsonb_build_object('conversation_id', NEW.conversation_id)
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 4. ADMIN RPC: Get all reports with user details
CREATE OR REPLACE FUNCTION get_admin_reports()
RETURNS TABLE (
  report_id UUID,
  reporter_id UUID,
  reporter_name TEXT,
  reporter_avatar TEXT,
  reporter_university TEXT,
  reported_user_id UUID,
  reported_name TEXT,
  reported_avatar TEXT,
  reported_university TEXT,
  category TEXT,
  description TEXT,
  conversation_id UUID,
  status TEXT,
  admin_notes TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    r.id AS report_id,
    r.reporter_id,
    rp.full_name AS reporter_name,
    rp.avatar_url AS reporter_avatar,
    rp.university AS reporter_university,
    r.reported_user_id,
    rup.full_name AS reported_name,
    rup.avatar_url AS reported_avatar,
    rup.university AS reported_university,
    r.category,
    r.description,
    r.conversation_id,
    r.status,
    r.admin_notes,
    r.created_at,
    r.updated_at
  FROM public.reports r
  JOIN public.users rp ON rp.id = r.reporter_id
  JOIN public.users rup ON rup.id = r.reported_user_id
  ORDER BY r.created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 5. ADMIN RPC: Get block status between users
CREATE OR REPLACE FUNCTION is_user_blocked(check_blocker_id UUID, check_blocked_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS(
    SELECT 1 FROM public.blocked_users
    WHERE blocker_id = check_blocker_id AND blocked_id = check_blocked_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 6. Enable realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.blocked_users;
ALTER PUBLICATION supabase_realtime ADD TABLE public.reports;
