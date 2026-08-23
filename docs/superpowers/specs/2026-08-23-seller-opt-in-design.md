# Seller Opt-In Design

**Date:** 2026-08-23
**Status:** Approved (design), pending spec review
**Branch:** `instiy`

## Problem

Every authenticated user currently sees the seller **Dashboard** tab in the bottom navigation, even though most users are (and want to remain) buyers. There is no concept of a "seller account" anywhere in the system: any authenticated user can insert products (`WITH CHECK (auth.uid() = seller_id)`), and the app infers seller-ness from the existence of products or a `business_profiles` row.

## Goal

Selling becomes an explicit, user-initiated, **irreversible** opt-in:

- Non-sellers see no Dashboard tab (mobile) and no Sell/Dashboard items (desktop).
- A **"Become a Seller"** item in the profile avatar dropdown launches a wizard.
- The wizard explains selling, warns that the change cannot be undone, collects a basic business profile, and flips a one-way `is_seller` flag on the account.
- The database enforces seller-only selling (products, services, business profiles) so modified or outdated clients cannot bypass the gate.

## Decisions (from brainstorming)

| Question | Decision |
|---|---|
| Source of truth | Explicit one-way `users.is_seller` flag, flipped exactly once by an RPC |
| Wizard scope | Info → irreversible warning + acknowledgment → business profile (inline) |
| Enforcement | DB-level (RLS on INSERT + SECURITY DEFINER RPC + ratchet trigger) |
| Backfill | Users with ≥1 product OR a business profile (3 of 4 current users) |
| Client state | Parse flag into existing `AppUser`/`AuthProvider`; no new provider |
| Flip mechanism | Single atomic `become_seller()` RPC (profile upsert + flag flip in one transaction) |

## Database

One migration, committed as `supabase/migrations/20260823HHMMSS_become_seller_opt_in.sql` and applied to the hosted project via the Supabase MCP (`apply_migration`, project `wqasatrxqinkfaafgnli`).

### 1. Column + backfill

```sql
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_seller boolean NOT NULL DEFAULT false;

-- One-time backfill: anyone who already sells or set up a shop stays a seller.
UPDATE public.users
SET is_seller = true, updated_at = now()
WHERE id IN (
  SELECT seller_id FROM public.products
  UNION
  SELECT seller_id FROM public.business_profiles
);
```

### 2. Helper function

```sql
CREATE OR REPLACE FUNCTION public.is_seller(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE
AS $$
  SELECT COALESCE(
    (SELECT u.is_seller FROM public.users u WHERE u.id = p_user_id),
    false
  );
$$;
```

`users` is world-readable under RLS (`USING (true)`), so a plain SQL (non-SECURITY-DEFINER) function is safe and avoids ownership pitfalls.

### 3. `become_seller` RPC

```sql
CREATE OR REPLACE FUNCTION public.become_seller(
  p_business_name text,
  p_description text,
  p_phone_numbers jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Must be signed in';
  END IF;
  IF p_business_name IS NULL OR length(btrim(p_business_name)) < 2 THEN
    RAISE EXCEPTION 'Business name is required';
  END IF;

  INSERT INTO public.business_profiles
    (seller_id, business_name, description, phone_numbers)
  VALUES
    (auth.uid(),
     btrim(p_business_name),
     NULLIF(btrim(COALESCE(p_description, '')), ''),
     COALESCE(p_phone_numbers, '[]'::jsonb))
  ON CONFLICT (seller_id) DO UPDATE
    SET business_name    = EXCLUDED.business_name,
        description      = EXCLUDED.description,
        phone_numbers    = EXCLUDED.phone_numbers,
        updated_at       = now();

  UPDATE public.users
  SET is_seller = true, updated_at = now()
  WHERE id = auth.uid() AND NOT is_seller;
END;
$$;

REVOKE ALL ON FUNCTION public.become_seller(text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.become_seller(text, text, jsonb) TO authenticated;
```

Properties: atomic (single transaction), idempotent (re-running updates the profile only; the flag UPDATE is a no-op once true), bypasses RLS via SECURITY DEFINER so a not-yet-seller can create their first business profile.

### 4. One-way ratchet trigger

Users can already UPDATE their own `users` row (`"Users can update own profile"` policy, no column restrictions), so the flag must be protected by a trigger, not just by the client never sending `false`:

```sql
CREATE OR REPLACE FUNCTION public.enforce_seller_ratchet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.is_seller AND NOT NEW.is_seller
     AND auth.uid() IS NOT NULL
     AND NOT public.is_admin(auth.uid()) THEN
    NEW.is_seller := true;  -- ratchet: sellers cannot un-become sellers
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_users_seller_ratchet ON public.users;
CREATE TRIGGER trigger_users_seller_ratchet
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_seller_ratchet();
```

The service role (`auth.uid() IS NULL`) and admins (`public.is_admin`) can still clear the flag for support/abuse cases — same escape-hatch pattern as the `is_verified` revoke flow.

### 5. RLS tightening (INSERT paths only)

Existing UPDATE/SELECT policies stay unchanged — sellers editing their own rows keep working.

```sql
-- products (replaces "Users can create own products")
DROP POLICY IF EXISTS "Users can create own products" ON public.products;
CREATE POLICY "Users can create own products"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));

-- services (replaces "Providers can create services")
DROP POLICY IF EXISTS "Providers can create services" ON public.services;
CREATE POLICY "Providers can create services"
  ON public.services FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = provider_id AND public.is_seller(auth.uid()));
```

```sql
-- business_profiles (replace both own-write policies; view policy unchanged)
DROP POLICY IF EXISTS "Sellers can insert own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can insert own business profile"
  ON public.business_profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));

DROP POLICY IF EXISTS "Sellers can update own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can update own business profile"
  ON public.business_profiles FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id AND public.is_seller(auth.uid()));
```

The wizard never hits these policies — it goes through the SECURITY DEFINER RPC.

## Client

### Model & state

- `lib/models/user_model.dart` — `AppUser` gains `final bool isSeller;` parsed from `is_seller`, wired through `fromJson` and `copyWith`.
- `lib/services/auth_service.dart` — `getCurrentUserProfile` selects `is_seller` too.
- `lib/services/seller_onboarding_service.dart` (new) — thin wrapper: validates inputs client-side, calls `Supabase.instance.client.rpc('become_seller', ...)`; caller then reloads `AuthProvider.loadUserProfile()`.
- No new provider: `AuthProvider` already re-syncs the signed-in user's own `users` row over Realtime (`auth_provider.dart` realtime resubscribe), so a flipped flag propagates to the UI automatically; the wizard also refreshes locally on success for instant feedback.

### Navigation gating

- `lib/widgets/app_bottom_nav.dart` — in the authed branch, the Dashboard `_navButton` renders only when `isSeller`. It stays **last** in the list so `_handleNavTap` indices (0–4) and each screen's hardcoded `AdaptiveNav(currentIndex:)` remain valid for non-sellers.
- `lib/widgets/app_top_nav.dart` (desktop) — "Sell" and "Dashboard" items render only for sellers; unauthenticated and non-seller layouts otherwise unchanged. Since screens pass a hardcoded `currentIndex`, the hidden items must not shift the position of Home/Explore/Clips/Messages (keep seller items last, same as the bottom nav).
- Route guards in `lib/main.dart` `onGenerateRoute`: `/seller-dashboard`, `/sell`, `/create-listing`, `/edit-business-profile` redirect non-sellers to `/become-seller` (covers deep links and stale installs hitting dead ends). Guards read `authProvider.user.isSeller`; unauthenticated users follow existing auth behavior.

### "Become a Seller" menu item

- `lib/widgets/user_avatar_menu.dart` — new `_buildMenuItem` (store icon, label "Become a Seller") placed between "Following" and "Settings", visible only when `!isSeller`; new `onBecomeSellerTap` callback prop, wired in `home_screen.dart` and `explore_screen.dart` (both already host `UserAvatarMenu`).

### Wizard — `lib/screens/seller/become_seller_screen.dart`

New route `/become-seller`, deferred-loaded via the `_DeferredLoader` pattern. Multi-step layout mirrors `seller_profile_verification_screen.dart` (frosted pill step indicator, per-step form keys, bottom Back/Next bar).

- **Step 1 — "Sell on Instiy":** what sellers get (product/service listings, wallet payouts, dashboard analytics, clips with reviews) and what's expected (fulfil orders, respond to buyers, follow policies).
- **Step 2 — "Before you continue":** prominent "This cannot be undone" callout; required checkbox acknowledging permanence; note that the verified badge is a separate, optional step.
- **Step 3 — "Your business profile":** business name (required, ≥2 chars), description (optional), phone numbers (same field semantics as `EditBusinessProfileScreen` core fields, stored as JSONB array).
- **Finish:** "Become a Seller" button → loading state → RPC → success view (checkmark, "Go to Dashboard" → `pushNamedAndRemoveUntil('/seller-dashboard')`). `AuthProvider` refresh makes the Dashboard tab appear immediately.

Behavior rules:

- Back navigation free until the final tap; cancel persists nothing.
- RPC failure → error toast (ShadToast), remain on step 3, inputs retained.
- Deep-linked users who are already sellers see an "You're already a seller" state with a go-to-dashboard action instead of the wizard.

## Error handling

| Case | Behavior |
|---|---|
| RPC network/validation failure | Toast with message; wizard stays on step 3, inputs kept |
| User backs out / closes wizard | Nothing persisted anywhere |
| Non-seller inserts product/service/profile (old client, tampered client) | Rejected by RLS with 42501; app surfaces the existing error path |
| Non-seller deep-links to seller routes | Guard redirects to `/become-seller` |
| User attempts `is_seller = false` on own row | Silently re-ratcheted to `true` by trigger |
| Wallet | Unchanged — every user already gets a wallet on signup |

## Testing & verification

1. `flutter analyze` clean.
2. Manual (run app):
   - Fresh buyer account: no Dashboard tab (mobile), no Sell/Dashboard (desktop), "Become a Seller" present in avatar menu.
   - Complete wizard: success view → Dashboard tab present, business profile created, flag set (verify via MCP `execute_sql`).
   - Cancel wizard mid-way: no `business_profiles` row, no flag.
   - Deep-link `/seller-dashboard` as non-seller → redirected to wizard.
   - Existing seller: edits business profile via dashboard (RLS UPDATE still allowed), avatar menu shows no "Become a Seller".
3. Database: `list_migrations` via MCP shows the new migration; `get_advisors(type=security)` clean of new findings.
4. Ratchet check via MCP: attempt `UPDATE users SET is_seller = false ...` as an authenticated non-admin — value stays `true`.

## Out of scope

- Admin panel UI for clearing the flag (admins/service role can do it via SQL when needed).
- Gating `seller_verifications` inserts (only reachable from the seller dashboard anyway).
- Any un-seller/self-demotion flow — explicitly rejected by design.
- Payout setup inside the wizard (wallet/withdrawals unchanged).
