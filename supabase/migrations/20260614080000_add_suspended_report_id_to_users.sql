-- Add a column to track which report triggered the suspension
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS suspended_report_id UUID REFERENCES public.reports(id) ON DELETE SET NULL;
