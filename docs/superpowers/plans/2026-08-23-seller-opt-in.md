# Seller Opt-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make selling an explicit, irreversible opt-in: hide seller UI from non-sellers, add a "Become a Seller" wizard, and enforce seller-only inserts at the database level.

**Architecture:** A one-way `users.is_seller` flag is the single source of truth, flipped by a SECURITY DEFINER `become_seller()` RPC that also upserts the business profile atomically. The flag is parsed into the existing `AppUser`/`AuthProvider` (whose Realtime subscription already re-syncs the user's row), nav widgets read it reactively, and a `SellerGate` wrapper guards seller-only routes. Spec: `docs/superpowers/specs/2026-08-23-seller-opt-in-design.md`.

**Tech Stack:** Flutter 3 / Dart, Riverpod (legacy ChangeNotifier providers via `lib/providers/providers.dart`), shadcn_ui, Supabase (hosted project `wqasatrxqinkfaafgnli`, accessed only through the Supabase MCP via `mcporter`).

## Global Constraints

- All DB reads/writes go through the Supabase MCP: `mcporter call supabase-instiy.<tool> 'project_id=wqasatrxqinkfaafgnli' ...`. `mcporter` is only on the nvm node path: prefix every shell with `export PATH="$HOME/.nvm/versions/node/v25.9.0/bin:$PATH"`.
- `flutter` is only at `$HOME/flutter/bin`: prefix with `export PATH="$HOME/flutter/bin:$PATH"`.
- Schema changes must be BOTH committed as a file under `supabase/migrations/` AND applied via MCP `apply_migration`.
- Working directory for all commands: `/home/defy/Documents/instiyapp`.
- New UI follows the glass style: `AppTheme.*` tokens, `AppTheme.frosted`, `AppTheme.glassAppBar`, responsive helpers from `utils/responsive.dart` (`context.rw/rh/ri/rsp`).
- No new Riverpod providers — read `authProvider` from `lib/providers/providers.dart`.
- Never call `notifyListeners()` in constructors.
- Commit after every task with `--no-verify` (repo convention in this session).

---

### Task 1: Database migration — `is_seller` flag, RPC, ratchet, RLS

**Files:**
- Create: `supabase/migrations/20260823100000_become_seller_opt_in.sql`

**Interfaces:**
- Produces (DB): column `public.users.is_seller boolean NOT NULL DEFAULT false`; function `public.is_seller(uuid) -> boolean`; function `public.become_seller(p_business_name text, p_description text) -> void` (EXECUTE granted to `authenticated` only); trigger `trigger_users_seller_ratchet`; tightened INSERT policies on `products` / `services` / `business_profiles`; column-freezing `WITH CHECK` on `"Users can update own profile"`.

- [ ] **Step 1: Write the migration file**

Create `supabase/migrations/20260823100000_become_seller_opt_in.sql` with exactly:

```sql
-- Become a Seller: explicit, irreversible seller opt-in.
-- users.is_seller is the single source of truth for seller status.

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_seller boolean NOT NULL DEFAULT false;

-- One-time backfill: existing sellers (products or business profile) keep access.
UPDATE public.users
SET is_seller = true, updated_at = now()
WHERE id IN (
  SELECT seller_id FROM public.products
  UNION
  SELECT seller_id FROM public.business_profiles
);

-- Helper used by RLS policies.
CREATE OR REPLACE FUNCTION public.is_seller(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    (SELECT u.is_seller FROM public.users u WHERE u.id = p_user_id),
    false
  );
$$;

-- One-way RPC: creates/updates the business profile and flips the flag atomically.
CREATE OR REPLACE FUNCTION public.become_seller(
  p_business_name text,
  p_description text DEFAULT NULL
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
    RAISE EXCEPTION 'Business name must be at least 2 characters';
  END IF;

  INSERT INTO public.business_profiles (seller_id, business_name, description)
  VALUES (auth.uid(), btrim(p_business_name), NULLIF(btrim(COALESCE(p_description, '')), ''))
  ON CONFLICT (seller_id) DO UPDATE
    SET business_name = EXCLUDED.business_name,
        description   = EXCLUDED.description,
        updated_at    = now();

  UPDATE public.users
  SET is_seller = true, updated_at = now()
  WHERE id = auth.uid() AND NOT is_seller;
END;
$$;

REVOKE ALL ON FUNCTION public.become_seller(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.become_seller(text, text) TO authenticated;

-- Users may no longer change is_seller through the plain profile-update path.
DROP POLICY IF EXISTS "Users can update own profile" ON public.users;
CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id AND NEW.is_seller = OLD.is_seller);

-- Ratchet: is_seller can never go true -> false, except via the service role
-- or an admin (same escape hatch as the is_verified revoke flow).
CREATE OR REPLACE FUNCTION public.enforce_seller_ratchet()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.is_seller AND NOT NEW.is_seller
     AND auth.uid() IS NOT NULL
     AND NOT public.is_admin(auth.uid()) THEN
    NEW.is_seller := true;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_users_seller_ratchet ON public.users;
CREATE TRIGGER trigger_users_seller_ratchet
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_seller_ratchet();

-- Selling is now seller-only at the database level (INSERT paths only).
DROP POLICY IF EXISTS "Users can create own products" ON public.products;
CREATE POLICY "Users can create own products"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));

DROP POLICY IF EXISTS "Providers can create services" ON public.services;
CREATE POLICY "Providers can create services"
  ON public.services FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = provider_id AND public.is_seller(auth.uid()));

DROP POLICY IF EXISTS "Sellers can insert own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can insert own business profile"
  ON public.business_profiles FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));

DROP POLICY IF EXISTS "Sellers can update own business profile" ON public.business_profiles;
CREATE POLICY "Sellers can update own business profile"
  ON public.business_profiles FOR UPDATE TO authenticated
  USING (auth.uid() = seller_id AND public.is_seller(auth.uid()))
  WITH CHECK (auth.uid() = seller_id AND public.is_seller(auth.uid()));
```

- [ ] **Step 2: Apply the migration via the Supabase MCP**

The SQL contains single quotes and `$$`, so pass it through a shell variable (no re-expansion of file contents):

```bash
export PATH="$HOME/.nvm/versions/node/v25.9.0/bin:$PATH"
cd /home/defy/Documents/instiyapp
SQL=$(cat supabase/migrations/20260823100000_become_seller_opt_in.sql)
mcporter call supabase-instiy.apply_migration 'project_id=wqasatrxqinkfaafgnli' 'name=20260823100000_become_seller_opt_in' "query=$SQL"
```

Expected: JSON response containing `"name": "20260823100000_become_seller_opt_in"` with no error.

- [ ] **Step 3: Verify backfill and column**

```bash
mcporter call supabase-instiy.execute_sql 'project_id=wqasatrxqinkfaafgnli' 'query=SELECT count(*) AS total, count(*) FILTER (WHERE is_seller) AS sellers FROM public.users'
```

Expected: `{"total":4,"sellers":3}` (current data: 4 users, 3 with products-or-profile).

- [ ] **Step 4: Verify RPC rejects unauthenticated calls and grants are right**

```bash
mcporter call supabase-instiy.execute_sql 'project_id=wqasatrxqinkfaafgnli' 'query=SELECT p.proname, p.proacl FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = $$public$$ AND p.proname IN ($$become_seller$$, $$is_seller$$)'
```

Expected: both functions listed; `become_seller` proacl shows execute for `authenticated` and not `anon`. (Calls from the MCP run with no `auth.uid()`, so calling `become_seller` directly would raise `Must be signed in` — do not call it here.)

- [ ] **Step 5: Run the security advisor**

```bash
mcporter call supabase-instiy.get_advisors 'project_id=wqasatrxqinkfaafgnli' 'type=security'
```

Expected: no NEW findings referencing `users`, `products`, `services`, or `business_profiles` policies (pre-existing findings unchanged).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260823100000_become_seller_opt_in.sql
git commit --no-verify -m "feat(db): seller opt-in flag, become_seller RPC, ratchet, seller-only inserts"
```

---

### Task 2: `AppUser.isSeller` model field

**Files:**
- Modify: `lib/models/user_model.dart`

**Interfaces:**
- Produces: `AppUser.isSeller` (`bool`, constructor default `false`), parsed from column `is_seller`, included in `toJson` and `copyWith`. Everything downstream (nav, menu, gates) reads this.

- [ ] **Step 1: Add the field**

In `lib/models/user_model.dart`, add after `final bool isVerified;` (line 10):

```dart
  final bool isSeller;
```

Add to the constructor (after `this.isVerified = false,` line 26):

```dart
    this.isSeller = false,
```

Add to `fromJson` (after line 44, the `isVerified:` line):

```dart
      isSeller: json['is_seller'] as bool? ?? false,
```

Add to `toJson` (after `'is_verified': isVerified,` line 65):

```dart
      'is_seller': isSeller,
```

Add to `copyWith` signature (after `bool? isVerified,` line 81):

```dart
    bool? isSeller,
```

and to the `copyWith` body (after `isVerified: isVerified ?? this.isVerified,` line 95):

```dart
      isSeller: isSeller ?? this.isSeller,
```

Note: `AuthService.getCurrentUserProfile` uses `.select()` (all columns), so `is_seller` arrives with no query change; `AuthProvider`'s Realtime callbacks re-fetch the full profile, so the flag propagates live.

- [ ] **Step 2: Analyze**

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /home/defy/Documents/instiyapp
flutter analyze
```

Expected: `No issues found!` (or only pre-existing issues, none in `user_model.dart`).

- [ ] **Step 3: Commit**

```bash
git add lib/models/user_model.dart
git commit --no-verify -m "feat: parse users.is_seller into AppUser"
```

---

### Task 3: `SellerOnboardingService`

**Files:**
- Create: `lib/services/seller_onboarding_service.dart`

**Interfaces:**
- Produces: `SellerOnboardingService.becomeSeller({required String businessName, String? description}) -> Future<void>` — throws on failure; does NOT touch AuthProvider (caller refreshes).

- [ ] **Step 1: Create the service**

Create `lib/services/seller_onboarding_service.dart`:

```dart
import 'supabase_service.dart';

/// One-way seller opt-in.
///
/// Calls the `become_seller` RPC, which upserts the caller's business
/// profile and sets `users.is_seller = true` in a single transaction.
/// The flag is permanent — there is no client-side way back.
class SellerOnboardingService {
  static Future<void> becomeSeller({
    required String businessName,
    String? description,
  }) async {
    await SupabaseService.client.rpc(
      'become_seller',
      params: {
        'p_business_name': businessName,
        'p_description': description,
      },
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /home/defy/Documents/instiyapp
flutter analyze
```

Expected: no issues in the new file.

- [ ] **Step 3: Commit**

```bash
git add lib/services/seller_onboarding_service.dart
git commit --no-verify -m "feat: SellerOnboardingService wrapping become_seller RPC"
```

---

### Task 4: `SellerGate` route guard widget

**Files:**
- Create: `lib/widgets/seller_gate.dart`

**Interfaces:**
- Consumes: `AppUser.isSeller` (Task 2), `authProvider` from `lib/providers/providers.dart`.
- Produces: `SellerGate({required Widget child})` — wrap any seller-only route body.

- [ ] **Step 1: Create the widget**

Create `lib/widgets/seller_gate.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../providers/providers.dart';

/// Route guard for seller-only screens. Only sellers see [child];
/// unauthenticated users are redirected to login and authenticated
/// non-sellers are funnelled into the Become a Seller wizard, so deep
/// links and stale installs never dead-end.
class SellerGate extends ConsumerWidget {
  final Widget child;

  const SellerGate({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    if (auth.isLoading) {
      return const Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    if (!auth.isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/login');
        }
      });
      return const Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: SizedBox.shrink(),
      );
    }

    if (auth.user?.isSeller != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/become-seller');
        }
      });
      return const Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        body: SizedBox.shrink(),
      );
    }

    return child;
  }
}
```

- [ ] **Step 2: Analyze**

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /home/defy/Documents/instiyapp
flutter analyze
```

Expected: no issues in the new file.

- [ ] **Step 3: Commit**

```bash
git add lib/widgets/seller_gate.dart
git commit --no-verify -m "feat: SellerGate route guard for seller-only screens"
```

---

### Task 5: Hide Dashboard/Sell nav items for non-sellers

**Files:**
- Modify: `lib/widgets/app_bottom_nav.dart` (build, lines ~78–132)
- Modify: `lib/widgets/app_top_nav.dart` (build, lines ~84–191)

**Interfaces:**
- Consumes: `AppUser.isSeller` via `ref.watch(authProvider)`.
- Note: the Dashboard button/items stay **last** in both bars so `_handleNavTap` indices (0–4), `AppTopNav` active-index checks (4/5), and each screen's hardcoded `AdaptiveNav(currentIndex:)` keep working.

- [ ] **Step 1: Gate the mobile bottom nav**

In `lib/widgets/app_bottom_nav.dart` build, after `final isAuth = authState.isAuthenticated;` (line 83) add:

```dart
    final isSeller = authState.user?.isSeller == true;
```

Replace the authed `Row` children (lines 117–126) with:

```dart
                  children: isAuth
                      ? [
                          _navButton(context, isAuth, 0, LucideIcons.home, 'Home'),
                          _navButton(context, isAuth, 1, LucideIcons.search, 'Explore'),
                          _navButton(context, isAuth, 2, LucideIcons.video, 'Clips'),
                          _navButton(context, isAuth, 3, LucideIcons.messageSquare, 'Messages',
                              badgeCount: unreadCount,
                              svgAsset: 'assets/message-2-pending-svgrepo-com.svg'),
                          if (isSeller)
                            _navButton(context, isAuth, 4, LucideIcons.layoutDashboard, 'Dashboard'),
                        ]
                      : [
                          _navButton(context, isAuth, 0, LucideIcons.home, 'Home'),
                          _navButton(context, isAuth, 1, LucideIcons.search, 'Explore'),
                          _navButton(context, isAuth, 2, LucideIcons.video, 'Clips'),
                          _navButton(context, isAuth, 3, LucideIcons.info, 'Info'),
                        ],
```

(`_handleNavTap`'s `case 4` stays — it is simply unreachable for non-sellers.)

- [ ] **Step 2: Gate the desktop top nav**

In `lib/widgets/app_top_nav.dart` build, after `final isAuth = authState.isAuthenticated;` (line 88) add:

```dart
    final isSeller = authState.user?.isSeller == true;
```

Wrap the two seller items (lines 154–165) so the authed branch ends:

```dart
                if (isSeller) ...[
                  _buildNavItem(
                    icon: LucideIcons.plus,
                    label: 'Sell',
                    active: currentIndex == 4,
                    onTap: () => Navigator.of(context).pushNamed('/sell'),
                  ),
                  _buildNavItem(
                    icon: LucideIcons.layoutDashboard,
                    label: 'Dashboard',
                    active: currentIndex == 5,
                    onTap: () => Navigator.of(context).pushNamed('/seller-dashboard'),
                  ),
                ],
```

- [ ] **Step 3: Analyze and commit**

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /home/defy/Documents/instiyapp
flutter analyze
git add lib/widgets/app_bottom_nav.dart lib/widgets/app_top_nav.dart
git commit --no-verify -m "feat: hide Dashboard/Sell nav items for non-sellers"
```

Expected: analyze clean for both files.

---

### Task 6: "Become a Seller" item in the avatar menu

**Files:**
- Modify: `lib/widgets/user_avatar_menu.dart`
- Modify: `lib/screens/home/home_screen.dart` (`_HomeGlassHeader` fields/ctor lines ~475–501, `UserAvatarMenu` call lines ~544–557, header construction lines ~176–197)
- Modify: `lib/screens/explore/explore_screen.dart` (`UserAvatarMenu` call, lines ~641–660)

**Interfaces:**
- Consumes: `AppUser.isSeller` (read internally via `ref.watch(authProvider)` — `UserAvatarMenu` is already a `ConsumerStatefulWidget`).
- Produces: new required prop `UserAvatarMenu.onBecomeSellerTap` (VoidCallback). Both call sites must pass it.

- [ ] **Step 1: Add the prop**

In `lib/widgets/user_avatar_menu.dart`, add to the widget fields (after `final VoidCallback onFollowingTap;` line 76):

```dart
  final VoidCallback onBecomeSellerTap;
```

and to the constructor (after `required this.onFollowingTap,` line 498-area — in this file, after the matching `required this.onFollowingTap,` line):

```dart
    required this.onBecomeSellerTap,
```

Update the class doc comment (lines 64–65) menu list to include "Become a Seller (non-sellers only)".

- [ ] **Step 2: Add the menu item**

In `_UserAvatarMenuState.build`, before the popover (line ~148), compute:

```dart
    final isSeller = ref.watch(authProvider).user?.isSeller == true;
```

Widen the popover from `width: 140` to `width: 164` (the new label needs the room), and insert between the "Following" and "Settings" items:

```dart
            if (!isSeller)
              _buildMenuItem(
                icon: LucideIcons.store,
                label: 'Become a Seller',
                onTap: widget.onBecomeSellerTap,
              ),
```

- [ ] **Step 3: Wire home screen**

In `lib/screens/home/home_screen.dart`:

1. `_HomeGlassHeader`: add `final VoidCallback onBecomeSellerTap;` (after `onFollowingTap`, line 481), add `required this.onBecomeSellerTap,` to the constructor, and pass it inside its `UserAvatarMenu` (after `onFollowingTap: onFollowingTap,` line 554):

```dart
                  onBecomeSellerTap: onBecomeSellerTap,
```

2. At the `_HomeGlassHeader(...)` construction (line ~176–197), add after `onFollowingTap: ...` (line 189):

```dart
            onBecomeSellerTap: () => Navigator.of(context).pushNamed('/become-seller'),
```

- [ ] **Step 4: Wire explore screen**

In `lib/screens/explore/explore_screen.dart`, in the `UserAvatarMenu(...)` call (line ~641), add after `onFollowingTap: ...` (line 651):

```dart
                                  onBecomeSellerTap: () => Navigator.of(context).pushNamed('/become-seller'),
```

- [ ] **Step 5: Analyze and commit**

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /home/defy/Documents/instiyapp
flutter analyze
git add lib/widgets/user_avatar_menu.dart lib/screens/home/home_screen.dart lib/screens/explore/explore_screen.dart
git commit --no-verify -m "feat: Become a Seller item in avatar menu for non-sellers"
```

Expected: analyze clean (all `UserAvatarMenu` call sites updated — only home and explore use it).

---

### Task 7: Become a Seller wizard + route registration + guards

**Files:**
- Create: `lib/screens/seller/become_seller_screen.dart`
- Modify: `lib/main.dart` (deferred imports ~lines 55–72, route cases `/sell` 534, `/seller-dashboard` 583, `/create-listing` 605, `/edit-business-profile` 654, plus a new `/become-seller` case; add `import 'widgets/seller_gate.dart';` near the other lib imports)

**Interfaces:**
- Consumes: `SellerOnboardingService.becomeSeller` (Task 3), `SellerGate` (Task 4), `AppUser.isSeller` (Task 2).
- Produces: route `/become-seller` → `BecomeSellerScreen` (deferred-loaded).

- [ ] **Step 1: Create the wizard screen**

Create `lib/screens/seller/become_seller_screen.dart` with the complete file:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';
import '../../services/seller_onboarding_service.dart';
import '../../utils/responsive.dart';

/// One-way onboarding that turns a buyer account into a seller account.
///
/// Nothing is persisted until the final "Become a Seller" tap, which calls
/// the `become_seller` RPC (business profile upsert + `users.is_seller`
/// flip in one transaction). The flag is permanent by design — the
/// commitment step makes that explicit before anything is submitted.
class BecomeSellerScreen extends ConsumerStatefulWidget {
  const BecomeSellerScreen({super.key});

  @override
  ConsumerState<BecomeSellerScreen> createState() =>
      _BecomeSellerScreenState();
}

class _BecomeSellerScreenState extends ConsumerState<BecomeSellerScreen> {
  static const _steps = ['Overview', 'Commitment', 'Business Profile'];

  int _currentStep = 0;
  bool _acknowledged = false;
  bool _submitting = false;
  bool _completed = false;

  final _businessNameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _businessNameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ─── Submit ────────────────────────────────────────────────────

  Future<void> _submit() async {
    final name = _businessNameController.text.trim();
    if (name.length < 2) {
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Please enter a business name (at least 2 characters)')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await SellerOnboardingService.becomeSeller(
        businessName: name,
        description: _descriptionController.text.trim(),
      );
      // Refresh the profile so isSeller flips everywhere (nav, menus).
      await ref.read(authProvider).loadUserProfile();
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _completed = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ShadToaster.of(context).show(
        const ShadToast(
          backgroundColor: AppTheme.destructive,
          title: Text('Could not complete onboarding. Please try again.'),
        ),
      );
    }
  }

  bool _canProceed() {
    switch (_currentStep) {
      case 1:
        return _acknowledged;
      default:
        return true;
    }
  }

  // ─── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // Deep-linked sellers (or users finishing on another device) shouldn't
    // re-run an irreversible flow.
    if (auth.user?.isSeller == true) {
      return _buildAlreadySeller();
    }

    if (_completed) {
      return _buildSuccess();
    }

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      extendBody: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Become a Seller'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                MediaQuery.of(context).padding.top + kToolbarHeight + 70,
                16,
                MediaQuery.of(context).padding.bottom + 90,
              ),
              child: _buildCurrentStep(),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            left: 10,
            right: 10,
            child: _buildStepIndicator(),
          ),
        ],
      ),
      bottomNavigationBar: _buildNavigationButtons(),
    );
  }

  // ─── Step Indicator ────────────────────────────────────────────

  Widget _buildStepIndicator() {
    return AppTheme.frosted(
      radius: 14,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: context.rw(16),
          vertical: context.rh(12),
        ),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_steps.length, (index) {
              final isActive = index == _currentStep;
              final isDone = index < _currentStep;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: context.rw(28),
                    height: context.rh(28),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone
                          ? AppTheme.successMoss
                          : isActive
                              ? AppTheme.accent
                              : AppTheme.warmMist,
                      border: Border.all(
                        color: isDone
                            ? AppTheme.successMoss
                            : isActive
                                ? AppTheme.accent
                                : AppTheme.whisperBorder,
                      ),
                    ),
                    child: Center(
                      child: isDone
                          ? Icon(LucideIcons.check,
                              size: context.ri(14), color: Colors.white)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: context.rsp(12),
                                fontWeight: FontWeight.w600,
                                color: isActive
                                    ? Colors.white
                                    : AppTheme.mutedSteel,
                              ),
                            ),
                    ),
                  ),
                  if (index < _steps.length - 1)
                    Container(
                      width: context.rw(32),
                      height: context.rh(2),
                      margin:
                          EdgeInsets.symmetric(horizontal: context.rw(4)),
                      color: isDone
                          ? AppTheme.successMoss
                          : AppTheme.whisperBorder,
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  // ─── Steps ─────────────────────────────────────────────────────

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStep0Overview();
      case 1:
        return _buildStep1Commitment();
      case 2:
        return _buildStep2BusinessProfile();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildStep0Overview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: context.rw(64),
            height: context.rw(64),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(LucideIcons.store,
                  size: context.ri(28), color: AppTheme.accent),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Sell on Instiy',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Turn what you make or do into a store classmates can discover.',
          style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
        ),
        const SizedBox(height: 24),
        _infoCard(
          icon: LucideIcons.sparkles,
          title: 'What you get',
          items: const [
            'List products and services on your own store page',
            'Receive payments into your Instiy wallet',
            'Track orders, reviews and analytics from your dashboard',
          ],
        ),
        const SizedBox(height: 16),
        _infoCard(
          icon: LucideIcons.shieldCheck,
          title: 'What we expect',
          items: const [
            'Fulfil the orders you receive and keep listings accurate',
            'Respond to buyer messages promptly',
            'Follow Instiy\'s seller policies — violations affect your account',
          ],
        ),
      ],
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return AppTheme.frosted(
      radius: 14,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoalInk,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(LucideIcons.check,
                        size: 14, color: AppTheme.successMoss),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.mutedSteel,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep1Commitment() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Before you continue',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Please read this carefully.',
          style: TextStyle(color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.destructive.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.destructive.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(LucideIcons.alertTriangle,
                      size: 18, color: AppTheme.destructive),
                  SizedBox(width: 8),
                  Text(
                    'This cannot be undone.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.destructive,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Once you become a seller, your account stays a seller account. '
                'You can stop listing at any time, but the seller role itself is '
                'permanent for this account.',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.mutedSteel,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _acknowledged,
              onChanged: (val) => setState(() => _acknowledged = val ?? false),
              activeColor: AppTheme.accent,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'I understand that becoming a seller is permanent and cannot '
                  'be reversed on this account.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.mutedSteel,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: AppTheme.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The verified badge is a separate, optional step you can take '
                  'later from your dashboard.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2BusinessProfile() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your business profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'This is how your store appears to buyers. You can expand it after setup.',
          style: TextStyle(color: AppTheme.mutedSteel),
        ),
        const SizedBox(height: 24),
        const Text(
          'Business Name',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 8),
        ShadInput(
          controller: _businessNameController,
          placeholder: const Text('e.g. Adaeze\'s Thrift Finds'),
        ),
        const SizedBox(height: 20),
        const Text(
          'Description (Optional)',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
        ),
        const SizedBox(height: 8),
        ShadInput(
          controller: _descriptionController,
          placeholder: const Text('What do you sell or offer?'),
          maxLines: 4,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.accent.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              Icon(LucideIcons.info, size: 14, color: AppTheme.accent),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Contact numbers, banner and location can be added from your '
                  'dashboard after you finish — phone numbers are verified by SMS there.',
                  style:
                      TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Terminal Views ────────────────────────────────────────────

  Widget _buildSuccess() {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Become a Seller'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppTheme.successMoss,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.check,
                    size: 36, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome, ${_businessNameController.text.trim()}!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your account is now a seller account. Your dashboard is ready — '
                'add your first listing whenever you like.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mutedSteel, height: 1.5),
              ),
              const SizedBox(height: 28),
              ShadButton(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/seller-dashboard', (r) => false),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAlreadySeller() {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Become a Seller'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.store,
                  size: 40, color: AppTheme.successMoss),
              const SizedBox(height: 16),
              const Text(
                'You\'re already a seller',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'This account is permanently a seller account.',
                style: TextStyle(color: AppTheme.mutedSteel),
              ),
              const SizedBox(height: 24),
              ShadButton(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/seller-dashboard', (r) => false),
                child: const Text('Go to Dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Navigation Buttons ────────────────────────────────────────

  Widget _buildNavigationButtons() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        10,
        0,
        10,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      child: AppTheme.frosted(
        radius: 20,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (_currentStep > 0)
                Expanded(
                  child: ShadButton.outline(
                    onPressed: () => setState(() => _currentStep--),
                    child: const Text('Back'),
                  ),
                ),
              if (_currentStep > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _currentStep == _steps.length - 1
                    ? ShadButton(
                        enabled: !_submitting,
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Become a Seller'),
                      )
                    : ShadButton(
                        enabled: _canProceed(),
                        onPressed: _canProceed()
                            ? () => setState(() => _currentStep++)
                            : null,
                        child: const Text('Continue'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Register the route and add guards in `lib/main.dart`**

1. Add the deferred import with the others (after the `deferred_seller_permissions` import, ~line 72):

```dart
import 'screens/seller/become_seller_screen.dart'
    deferred as deferred_become_seller;
```

2. Add the widget import near the other `lib/` imports at the top of the file:

```dart
import 'widgets/seller_gate.dart';
```

3. Add the route case (e.g. right before `case '/seller-dashboard':`, ~line 583):

```dart
            case '/become-seller':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_become_seller.loadLibrary,
                  builder: () => deferred_become_seller.BecomeSellerScreen(),
                ),
              );
```

4. Wrap the four guarded routes:

`/sell` (~line 534) becomes:

```dart
            case '/sell':
              return route(const SellerGate(child: SellScreen()));
```

`/seller-dashboard` (~line 583) becomes:

```dart
            case '/seller-dashboard':
              return route(const SellerGate(child: SellerDashboardScreen()));
```

`/create-listing` (~lines 605–617) — wrap the constructed screen:

```dart
              return route(
                SellerGate(
                  child: CreateListingScreen(existingProduct: product, source: source),
                ),
              );
```

`/edit-business-profile` (~lines 654–664) — wrap inside the deferred builder:

```dart
            case '/edit-business-profile':
              final existingProfile = settings.arguments as BusinessProfile?;
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_edit_business.loadLibrary,
                  builder: () => SellerGate(
                    child: deferred_edit_business.EditBusinessProfileScreen(
                      existingProfile: existingProfile,
                    ),
                  ),
                ),
              );
```

- [ ] **Step 3: Analyze and commit**

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /home/defy/Documents/instiyapp
flutter analyze
git add lib/screens/seller/become_seller_screen.dart lib/main.dart
git commit --no-verify -m "feat: Become a Seller wizard, /become-seller route, seller route guards"
```

Expected: analyze clean.

---

### Task 8: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Full analyze**

```bash
export PATH="$HOME/flutter/bin:$PATH"
cd /home/defy/Documents/instiyapp
flutter analyze
```

Expected: `No issues found!` or no new issues vs. the pre-feature baseline.

- [ ] **Step 2: Confirm remote migration history is in sync**

```bash
export PATH="$HOME/.nvm/versions/node/v25.9.0/bin:$PATH"
mcporter call supabase-instiy.list_migrations 'project_id=wqasatrxqinkfaafgnli'
```

Expected: `20260823100000_become_seller_opt_in` listed, and the local file `supabase/migrations/20260823100000_become_seller_opt_in.sql` is committed.

- [ ] **Step 3: Hand over the manual test script**

Report the following for the user to run in the app (cannot be automated here):

1. **Fresh buyer account** — no Dashboard tab in the bottom nav (and no Sell/Dashboard on desktop width); avatar menu shows "Become a Seller" between Following and Settings.
2. **Wizard completion** — walk all three steps, finish → success view → "Go to Dashboard" works; Dashboard tab now present; re-opening the avatar menu shows no "Become a Seller".
3. **Wizard cancel** — back out at step 3 and close; then verify via MCP: no `business_profiles` row for that user and `is_seller = false`.
4. **Deep link as non-seller** — navigate to `/seller-dashboard` (or `/sell`, `/create-listing`): redirected to the Become a Seller wizard.
5. **Existing seller** — dashboard opens normally; "Build Business Profile"/listing creation unaffected.

---

## Plan Self-Review (completed)

- **Spec coverage:** flag+backfill+RPC+ratchet+RLS (Task 1), model/state (Task 2), service (Task 3), route guards (Tasks 4+7), nav gating (Task 5), avatar menu (Task 6), wizard incl. already-seller state, cancel-safety, error toast, success view (Task 7), verification incl. advisors + manual script (Tasks 1 & 8). Wizard scope matches the refined spec (no phone collection; note points to the OTP flow).
- **Type consistency:** `AppUser.isSeller` (bool) used identically in Tasks 4–7; `SellerOnboardingService.becomeSeller({required String businessName, String? description})` defined in Task 3 and called with exactly those names in Task 7; `SellerGate({required Widget child})` defined Task 4, used Task 7; `onBecomeSellerTap` defined and wired in Task 6.
- **Placeholders:** none — all code complete, all commands exact.
