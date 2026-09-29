-- Threaded replies for service reviews, mirroring product_reviews
-- (20260530250000_unlimited_review_hierarchy.sql).
--
-- 1. parent_id links a reply to its top-level review (cascades on delete).
-- 2. rating becomes nullable so replies don't need star ratings.
-- 3. The one-review-per-user rule now applies to top-level reviews only,
--    enforced by a partial unique index so users can post unlimited replies.
-- 4. The services rollup trigger counts top-level reviews only.

ALTER TABLE public.service_reviews
  ADD COLUMN IF NOT EXISTS parent_id UUID
  REFERENCES public.service_reviews(id) ON DELETE CASCADE;

ALTER TABLE public.service_reviews ALTER COLUMN rating DROP NOT NULL;

ALTER TABLE public.service_reviews
  DROP CONSTRAINT IF EXISTS service_reviews_service_id_reviewer_id_key;

DROP INDEX IF EXISTS public.idx_service_reviews_unique_top_level;
CREATE UNIQUE INDEX idx_service_reviews_unique_top_level
  ON public.service_reviews (service_id, reviewer_id)
  WHERE (parent_id IS NULL);

CREATE INDEX IF NOT EXISTS idx_service_reviews_parent_id
  ON public.service_reviews (parent_id);

CREATE OR REPLACE FUNCTION public.sync_service_review_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_service_id uuid;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_service_id := OLD.service_id;
  ELSE
    v_service_id := NEW.service_id;
  END IF;

  UPDATE public.services s
  SET average_rating = COALESCE(
    (SELECT ROUND(AVG(r.rating)::numeric, 2)
       FROM public.service_reviews r
      WHERE r.service_id = s.id AND r.parent_id IS NULL),
    0),
    review_count = (SELECT count(*)
                      FROM public.service_reviews r
                     WHERE r.service_id = s.id AND r.parent_id IS NULL)
  WHERE s.id = v_service_id;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;
