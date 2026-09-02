# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Stack

- **Frontend**: Flutter + shadcn_ui
- **State**: Riverpod (ChangeNotifier hybrid + code generation via `@riverpod`)
- **Backend**: Supabase (Postgres, Auth, Realtime, Storage)
- **Storage**: Cloudflare R2 (via API proxy, not direct keys)
- **Local Cache**: Hive (`products_cache`) + SharedPreferences
- **Platform**: Android & iOS
- **Push**: Firebase Cloud Messaging + `flutter_local_notifications`
- **Payments**: Paystack (SDK + Cloudflare Workers)
- **Workers**: Cloudflare Workers at `api.instiy.com`

---

## Common Commands

```bash
flutter pub get                          # Install dependencies
flutter run                              # Debug run
flutter run --release                    # Release build (R8 enabled)
flutter analyze                          # Lint check (0 errors required)
flutter test                             # Run tests

# Code generation (Riverpod / Hive adapters)
dart run build_runner build --delete-conflicting-outputs   # After editing @riverpod files

# Splash screen (after logo changes)
python3 scratch/gen_splash.py
dart run flutter_native_splash:create

# Supabase migrations
npx supabase login
npx supabase db push          # Push migrations to hosted DB

# Cloudflare Workers
cd instiy-workers && npx wrangler dev   # Local dev
cd instiy-workers && npx wrangler deploy
```

---

## Architecture Overview

### Directory Structure (`lib/`)
```
config/      App-wide constants (AppConfig) and theming (AppTheme)
models/      Plain Dart data classes with fromJson / toJson
services/    Stateless static-method classes talking to Supabase/HTTP/platform
providers/   Riverpod providers + ChangeNotifier state holders (UI-facing state)
repositories ProductRepository — cache-first stream layer between UI and Supabase
screens/     One folder per feature; each screen is a StatefulWidget/Consumer
widgets/     Reusable, mostly stateless UI components
utils/       Pure helpers (formatters, responsive, text)
main.dart    Bootstrap, routing table, deep-link wiring, deferred screen loading
```

**Layering rule**: `screens` → `providers` → `services`/`repositories` → Supabase.  
Widgets never call services directly except for trivial, self-contained actions.

---

## Critical Boot Path (DO NOT REGRESS)

`main()` is intentionally minimal so the first frame renders fast:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. `appInitialization = _initializeApp()` assigned but **not awaited** in `main()`. The splash screen awaits it.
3. `runApp(const InstiyApp())` runs immediately.

**`_initializeApp()` (critical path — what the splash waits on)**:
- `SupabaseService.initialize()` — session restore (needed for auth gating)
- `HiveCacheService.initialize()` — opens the product cache box (offline-first home feed)

**Everything else is deferred** via `_initializeDeferred()` (fire-and-forget):
- Firebase + local notifications init
- FCM listener setup
- `SecretsService.instance.initialize()` — remote secret overrides

### Rules for Keeping Cold Boot Fast
- **Never** add a blocking `await` to `_initializeApp()` that performs network I/O. Put it in `_initializeDeferred()` instead.
- `SecretsService` exposes safe local defaults — secrets must stay deferred. Code paths needing fresh secrets (payments) call `SecretsService.instance.ensureLoaded()` on demand (see `PaystackService`).
- Rarely-used screens are **deferred imports** in `main.dart` (`deferred as ...`) and loaded via `_DeferredLoader`. Keep high-traffic screens eagerly imported.

---

## Routing & Deep Links

- All routes defined in `InstiyApp.onGenerateRoute` in `main.dart`
- Transitions use `AppTheme.fadeSlideRoute`
- Deep links (`app_links`) handled by `NavigationService`:
  - Cold-start links buffered in `NavigationService.pendingDeepLink` and consumed by splash after animation
  - Foreground links de-duplicated (`_handledLinks`) and suppressed during 3s post-resume grace period (ignores stale OEM Activity-recreation re-emissions)
- Supported schemes: `https://instiy.com/products/...` & `/store/...`, custom `io.supabase.instiy://product|store/...`, and share-product Worker URL

---

## Services Conventions

- Services are classes with **static methods** and no instance state (except singletons like `SecretsService.instance`)
- Network calls go through either:
  - `SupabaseService.client` (Postgres / auth / realtime), or
  - `SupabaseService.callFunction(name, body:)` / `getFunction(name)` for Cloudflare Workers (30s timeout, attaches JWT + apikey)
- Always wrap I/O in try/catch, log with `debugPrint`, fail gracefully. Never use `print` (lint-enforced).

---

## State Management

- Global providers declared in `lib/providers/providers.dart` as `ChangeNotifierProvider`s
- New, self-contained async state should prefer Riverpod code generation (`@riverpod` + `build_runner`), e.g. `home_products_riverpod.dart`
- After editing any `@riverpod`-annotated file, run:
  `dart run build_runner build --delete-conflicting-outputs`

---

## Offline-First Data

`ProductRepository.watchProducts()` is the template for cache-first data:

1. Emit cached data from Hive immediately (no shimmer on warm boot)
2. Fetch fresh data from Supabase
3. Write back to Hive
4. Emit fresh data

Network failures are swallowed after the cache has been emitted so the UI stays intact offline.

---

## Design System — "Trust Purple" Glassmorphism

See `ARCHITECTURE.md` §13 for the full palette, glassmorphism helpers, and dropdown/select styling rules.

Key tokens in `AppTheme`: `canvasWhite` (#FAF5FF), `accent` (#7C3AED), `accentBright` (#9F67FF), `charcoalInk` (#3B0764), `mutedSteel` (#6D5B8A), `whisperBorder` (#E9D5FF).

- Use `AppTheme.frosted()`, `AppTheme.glassDecoration()`, `AppTheme.glassAppBar()` — never hand-roll blur
- Glass is **translucent** (white 18–35% alpha), not opaque
- Text is deep violet on pale lilac — never grey-on-grey
- Light-theme only — do not introduce dark mode

---

## Git & PR Rules

- **Do NOT add `Co-authored-by` trailers** to git commits or pull request descriptions. The user has explicitly excluded these.
- Do NOT use `--trailer` or `-m` flags that append Co-authored-by lines.
- When creating commits, use simple `git commit -m "..."` without any author trailers.

---

## Research-First Implementation

Before implementing ANY new idea, feature, library, or pattern:

1. **Search first** — Use the **`agent-reach`** skill to find documentation, best practices, known issues
2. **Read the docs** — Use `agent-reach` to fetch and read official documentation
3. **Evaluate** — Check for:
   - Is this the right approach? Are there better alternatives?
   - Known bugs, breaking changes, or deprecation warnings
   - Version compatibility with existing dependencies
   - Community consensus on the pattern
4. **Then implement** — Only after research confirms the approach is sound

### When to research
- Adding a new dependency or plugin
- Fixing a cryptic error or warning
- Implementing a pattern you haven't seen in this codebase
- Upgrading dependencies
- Configuring build tools (Gradle, Xcode, etc.)
- Anything involving Android/iOS native configuration

### When you can skip research
- Editing existing code that you've already read and understood
- Simple bug fixes with clear error messages
- Styling/UI changes using existing app theme tokens
- Following patterns already established in the codebase

---

## Conventions Checklist (Before Committing)

- [ ] `flutter analyze` reports **0 errors**
- [ ] No `print()` in `lib/` (use `debugPrint`)
- [ ] No blocking network `await` added to `_initializeApp()`
- [ ] Secrets-dependent code calls `SecretsService.ensureLoaded()`
- [ ] New rarely-used screens are deferred-imported in `main.dart`
- [ ] `BuildContext` not used across an `await` without a `mounted` check
- [ ] Splash assets regenerated if the logo changed
- [ ] No `Co-authored-by` trailers in commits or PRs

---

## Key Files to Know

| File | Purpose |
|------|---------|
| `lib/main.dart` | App bootstrap, routing, deep links, deferred loading |
| `lib/config/app_theme.dart` | Design system, glassmorphism helpers, palette |
| `lib/config/app_config.dart` | API keys, URLs, constants |
| `lib/services/supabase_service.dart` | Supabase client, Cloudflare Worker calls |
| `lib/services/hive_cache_service.dart` | Hive initialization, cache boxes |
| `lib/services/product_repository.dart` | Cache-first product data stream |
| `lib/services/navigation_service.dart` | Deep link handling, navigation utilities |
| `lib/providers/providers.dart` | All global providers |
| `lib/models/product_model.dart` | Core product model with fromJson/toJson |
| `lib/services/secrets_service.dart` | Remote secret overrides with local defaults |
| `lib/services/local_notification_service.dart` | FCM + local notifications (two Android channels) |

---

## Deployment (TestFlight Pipeline)

When pushing commits or triggering iOS builds, the repo must be temporarily switched to **public** (macOS GitHub Actions runners require it):

1. `echo "y" | gh repo edit sthashixi-netwanderer/instiy-app --visibility public`
2. Push or trigger: `git push origin instiy` / `gh workflow run ios.yml --ref instiy`
3. Monitor: `gh run watch <run-id>`
4. **Immediately after** pipeline finishes (success or fail): `echo "y" | gh repo edit sthashixi-netwanderer/instiy-app --visibility private`

---

## Related Files

- `AGENTS.md` — Full package reference with docs URLs and agent workflow
- `ARCHITECTURE.md` — Detailed architecture guide (this file summarizes it)
- `INSTRUCTIONS.md` — Project instructions and coding workflow principles
