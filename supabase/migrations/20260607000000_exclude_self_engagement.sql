-- Trigger for video_views: exclude seller's own views
CREATE OR REPLACE FUNCTION public.check_video_view_self()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_id UUID;
BEGIN
  IF NEW.viewer_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT seller_id INTO v_seller_id FROM public.products WHERE id = NEW.product_id;
  IF v_seller_id = NEW.viewer_id THEN
    RETURN NULL; -- cancel insert silently
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_exclude_self_video_views ON public.video_views;
CREATE TRIGGER trg_exclude_self_video_views
  BEFORE INSERT ON public.video_views
  FOR EACH ROW
  EXECUTE FUNCTION public.check_video_view_self();

-- Trigger for video_shares: exclude seller's own shares
CREATE OR REPLACE FUNCTION public.check_video_share_self()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_id UUID;
BEGIN
  IF NEW.sharer_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT seller_id INTO v_seller_id FROM public.products WHERE id = NEW.product_id;
  IF v_seller_id = NEW.sharer_id THEN
    RETURN NULL; -- cancel insert silently
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_exclude_self_video_shares ON public.video_shares;
CREATE TRIGGER trg_exclude_self_video_shares
  BEFORE INSERT ON public.video_shares
  FOR EACH ROW
  EXECUTE FUNCTION public.check_video_share_self();

-- Trigger for favorites: exclude seller's own likes/favorites
CREATE OR REPLACE FUNCTION public.check_favorite_self()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_id UUID;
BEGIN
  SELECT seller_id INTO v_seller_id FROM public.products WHERE id = NEW.product_id;
  IF v_seller_id = NEW.user_id THEN
    RETURN NULL; -- cancel insert silently
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_exclude_self_favorites ON public.favorites;
CREATE TRIGGER trg_exclude_self_favorites
  BEFORE INSERT ON public.favorites
  FOR EACH ROW
  EXECUTE FUNCTION public.check_favorite_self();
