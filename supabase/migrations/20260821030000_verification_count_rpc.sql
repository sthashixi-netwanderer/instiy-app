-- Function to get count of pending verifications
CREATE OR REPLACE FUNCTION get_unread_verification_count()
RETURNS INTEGER AS $$
  SELECT COUNT(*)::INTEGER
  FROM public.seller_verifications
  WHERE status = 'pending';
$$ LANGUAGE sql SECURITY DEFINER;