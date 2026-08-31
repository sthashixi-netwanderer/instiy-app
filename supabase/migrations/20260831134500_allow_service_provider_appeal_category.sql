-- Allow service_provider_appeal category in reports
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_category_check;
ALTER TABLE public.reports ADD CONSTRAINT reports_category_check CHECK (
  category = ANY (ARRAY[
    'spam'::text,
    'harassment'::text,
    'scam'::text,
    'inappropriate_content'::text,
    'fake_account'::text,
    'hate_speech'::text,
    'violence'::text,
    'illegal_activity'::text,
    'counterfeit'::text,
    'misleading_listing'::text,
    'prohibited_item'::text,
    'product_scam'::text,
    'stolen_property'::text,
    'price_gouging'::text,
    'service_scam'::text,
    'misleading_service'::text,
    'service_provider_appeal'::text,
    'other'::text
  ])
);

-- Update reports_check to allow self-reporting when it's an appeal or reported_user_id is null
ALTER TABLE public.reports DROP CONSTRAINT IF EXISTS reports_check;
ALTER TABLE public.reports ADD CONSTRAINT reports_check CHECK (
  reported_user_id IS NULL OR reporter_id <> reported_user_id OR category = 'service_provider_appeal'
);
