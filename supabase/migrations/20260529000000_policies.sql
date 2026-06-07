-- Migration: Create policies table for Privacy Policy and Terms & Conditions

-- 1. Create policies table
CREATE TABLE IF NOT EXISTS public.policies (
  id UUID DEFAULT extensions.uuid_generate_v4() PRIMARY KEY,
  policy_type TEXT NOT NULL UNIQUE CHECK (policy_type IN ('privacy_policy', 'terms_conditions')),
  title TEXT NOT NULL,
  content TEXT NOT NULL DEFAULT '',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Create updated_at trigger
CREATE TRIGGER update_policies_updated_at
  BEFORE UPDATE ON public.policies
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- 3. Insert default empty policies
INSERT INTO public.policies (policy_type, title, content) VALUES
  ('privacy_policy', 'Privacy Policy', '# Privacy Policy

*Last updated: May 2026*

Your privacy is important to us. This Privacy Policy explains how Instiy collects, uses, and protects your personal information.

## Information We Collect

We collect information you provide directly, including:
- Name, email, and phone number
- University affiliation
- Profile information and photos
- Product listings and transaction data

## How We Use Your Information

- To provide and maintain the marketplace
- To process transactions and communications
- To verify your identity as a student
- To improve our services

## Data Security

We implement appropriate security measures to protect your personal information against unauthorized access, alteration, or destruction.

## Contact Us

If you have questions about this Privacy Policy, please contact us through the app.'),
  ('terms_conditions', 'Terms & Conditions', '# Terms & Conditions

*Last updated: May 2026*

Welcome to Instiy. By using our platform, you agree to these Terms & Conditions.

## Eligibility

- You must be a current student at a recognized institution
- You must be at least 16 years old
- You must provide accurate registration information

## User Responsibilities

- You are responsible for all activity on your account
- You must not list prohibited or illegal items
- You must accurately describe your products
- You must honor your transactions

## Prohibited Items

- Illegal goods or substances
- Counterfeit or stolen items
- Hazardous materials
- Items violating intellectual property rights

## Limitation of Liability

Instiy is a marketplace platform. We are not responsible for the quality, safety, or legality of items listed, or the ability of sellers to complete transactions.

## Contact Us

If you have questions about these Terms, please contact us through the app.')
ON CONFLICT (policy_type) DO NOTHING;

-- 4. RLS policies
ALTER TABLE public.policies ENABLE ROW LEVEL SECURITY;

-- Everyone can read active policies
CREATE POLICY "Anyone can read active policies"
  ON public.policies FOR SELECT
  USING (is_active = true);

-- Admins can manage policies
CREATE POLICY "Admins can manage policies"
  ON public.policies FOR ALL
  TO authenticated
  USING (public.is_admin(auth.uid()));
