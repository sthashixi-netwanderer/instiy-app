# AGENTS.md — AI Agent Instructions

## Purpose

This file provides AI agents with a comprehensive reference of all packages used in the Instiy project. Before implementing any feature, fix, or modification, agents **must** read the relevant official documentation to understand the package's API, best practices, and known patterns.

---

## Core Principle: Research Before Implement

**Always consult official documentation before:**
- Using a package's API for the first time
- Debugging unexpected behavior
- Implementing features that rely on specific package functionality
- Upgrading or changing package versions

---

## Flutter Packages (pubspec.yaml)

### UI & Theming
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| shadcn_ui | ^0.54.0 | https://pub.dev/packages/shadcn_ui | Primary UI component library |
| google_fonts | ^8.1.0 | https://pub.dev/packages/google_fonts | Custom fonts |
| flutter_animate | ^4.5.2 | https://pub.dev/packages/flutter_animate | Animation effects (re-exported by shadcn_ui) |
| flutter_svg | ^2.0.16 | https://pub.dev/packages/flutter_svg | SVG rendering |
| flutter_markdown_plus | ^1.0.7 | https://pub.dev/packages/flutter_markdown_plus | Markdown rendering |
| qr_flutter | ^4.1.0 | https://pub.dev/packages/qr_flutter | QR code generation |

### State Management
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| flutter_riverpod | ^3.3.1 | https://pub.dev/packages/flutter_riverpod | Primary state management (migration in progress) |
| riverpod_annotation | ^4.0.2 | https://pub.dev/packages/riverpod_annotation | Riverpod code generation annotations |
| riverpod_generator | ^4.0.3 | https://pub.dev/packages/riverpod_generator | Code generation for Riverpod |
| provider | any | https://pub.dev/packages/provider | Legacy state management (being phased out) |

### Backend & Auth
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| supabase_flutter | ^2.8.0 | https://pub.dev/packages/supabase_flutter | Supabase SDK for Flutter |
| google_sign_in | ^7.2.0 | https://pub.dev/packages/google_sign_in | Google OAuth |
| firebase_core | ^4.9.0 | https://pub.dev/packages/firebase_core | Firebase initialization |
| firebase_messaging | ^16.2.2 | https://pub.dev/packages/firebase_messaging | Push notifications |
| firebase_crashlytics | ^5.2.7 | https://pub.dev/packages/firebase_crashlytics | Crash reporting |
| flutter_webrtc | ^1.6.0 | https://pub.dev/packages/flutter_webrtc | P2P voice/video calls (WebRTC). Signaling via Supabase Realtime private channels (`calls:<userId>` ring + `call:<callId>` media); RLS on `realtime.messages` required. TURN creds served through get-secrets (TURN_URL/USERNAME/CREDENTIAL env vars) |

### Image & Media
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| image_picker | ^1.1.2 | https://pub.dev/packages/image_picker | Camera/gallery image selection |
| image_cropper | ^8.1.0 | https://pub.dev/packages/image_cropper | Image cropping |
| cached_network_image | ^3.4.1 | https://pub.dev/packages/cached_network_image | Network image caching |
| flutter_cache_manager | ^3.4.2 | https://pub.dev/packages/flutter_cache_manager | Persistent file cache backend (`CategoryImageCacheManager` for category artwork) |
| image | ^4.3.0 | https://pub.dev/packages/image | Image manipulation |
| photo_view | ^0.15.0 | https://pub.dev/packages/photo_view | Zoomable image viewer |
| giphy_get | ^3.5.0 | https://pub.dev/packages/giphy_get | GIF/sticker support |
| video_player | ^2.9.1 | https://pub.dev/packages/video_player | Video playback |
| video_compress | 3.1.4 | https://pub.dev/packages/video_compress | Video compression |
| audioplayers | ^6.7.1 | https://pub.dev/packages/audioplayers | Audio playback |
| record | ^7.0.0 | https://pub.dev/packages/record | Audio recording |

### Scanning & Links
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| mobile_scanner | 7.2.0 | https://pub.dev/packages/mobile_scanner | QR/barcode scanning |
| app_links | ^7.1.1 | https://pub.dev/packages/app_links | Deep link handling |
| url_launcher | ^6.3.1 | https://pub.dev/packages/url_launcher | Open URLs/phone/WhatsApp |
| flutter_linkify | ^6.0.0 | https://pub.dev/packages/flutter_linkify | Auto-linkify text |

### Storage & Data
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| shared_preferences | ^2.5.3 | https://pub.dev/packages/shared_preferences | Key-value local storage |
| sqflite | ^2.4.3 | https://pub.dev/packages/sqflite | SQLite database |
| hive | ^2.2.3 | https://pub.dev/packages/hive | Fast local NoSQL database |
| hive_flutter | ^1.1.0 | https://pub.dev/packages/hive_flutter | Hive Flutter integration |
| path_provider | ^2.1.5 | https://pub.dev/packages/path_provider | Device file paths |
| path | ^1.9.1 | https://pub.dev/packages/path | Path manipulation |

### Utilities
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| http | ^1.2.2 | https://pub.dev/packages/http | HTTP client |
| uuid | ^4.5.1 | https://pub.dev/packages/uuid | UUID generation |
| crypto | ^3.0.3 | https://pub.dev/packages/crypto | Hashing/encryption |
| intl | ^0.20.2 | https://pub.dev/packages/intl | Date formatting & i18n |
| permission_handler | ^12.0.2 | https://pub.dev/packages/permission_handler | Runtime permissions |
| local_auth | ^3.0.1 | https://pub.dev/packages/local_auth | Biometric authentication |
| flutter_local_notifications | ^21.0.0 | https://pub.dev/packages/flutter_local_notifications | Local notifications |
| paystack_flutter_sdk | 0.0.1-alpha.2 | https://pub.dev/packages/paystack_flutter_sdk | Payment processing |
| gal | ^2.3.2 | https://pub.dev/packages/gallery_saver | Save to gallery |

### Dev Dependencies
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| flutter_lints | ^6.0.0 | https://pub.dev/packages/flutter_lints | Lint rules |
| flutter_native_splash | ^2.4.7 | https://pub.dev/packages/flutter_native_splash | Native splash screen |
| build_runner | ^2.15.0 | https://pub.dev/packages/build_runner | Code generation runner |

---

## Node.js Packages

### Root (package.json)
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| supabase | ^2.105.0 | https://www.npmjs.com/package/supabase | Supabase CLI |
| wrangler | ^4.98.0 | https://developers.cloudflare.com/workers/wrangler/ | Cloudflare Workers CLI |

### Workers (instiy-workers/package.json)
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| jose | ^5.9.0 | https://www.npmjs.com/package/jose | JWT signing/verification |
| @cloudflare/workers-types | ^4.20240923.0 | https://www.npmjs.com/package/@cloudflare/workers-types | TypeScript types for Workers |

### Admin Panel (instiy-admin/package.json)
| Package | Version | Docs URL | Notes |
|---------|---------|----------|-------|
| react | ^19.2.6 | https://react.dev | UI framework |
| react-dom | ^19.2.6 | https://react.dev | React DOM renderer |
| react-router-dom | ^7.15.1 | https://reactrouter.com | Client-side routing |
| @supabase/supabase-js | ^2.106.2 | https://supabase.com/docs/reference/javascript | Supabase JS client |
| @radix-ui/react-dialog | ^1.1.17 | https://www.radix-ui.com/primitives/docs/components/dialog | Accessible dialog component |
| lucide-react | ^1.16.0 | https://lucide.dev | Icon library |
| vite | ^8.0.12 | https://vitejs.dev | Build tool |
| typescript | ~6.0.2 | https://www.typescriptlang.org | Type system |

---

## Agent Workflow: Documentation Research

When working on a task involving specific packages:

1. **Load the agent-reach skill** for internet research capabilities
2. **Identify relevant packages** from the tables above
3. **Search for documentation** using Exa web search
4. **Read the official docs** via `r.jina.ai` prefix for clean readable text
5. **Implement following documented patterns**, not guesswork
6. **Verify implementation** against documentation examples

### Research Commands (agent-reach)

Load the `agent-reach` skill first, then use these commands:

```bash
# Web search for documentation
mcporter call 'exa.web_search_exa(query: "package_name flutter documentation", numResults: 5)'

# Read any documentation page directly
curl -s "https://r.jina.ai/https://pub.dev/packages/package_name"

# For Node packages
curl -s "https://r.jina.ai/https://www.npmjs.com/package/package_name"

# GitHub search for examples/patterns
gh search repos "package_name flutter example" --sort stars --limit 5
```

**Always use `r.jina.ai` prefix to read documentation pages** — it converts any webpage to clean readable text.

---

## Supabase MCP (Database Operations)

The Supabase MCP server is configured for this project via mcporter (project-local, gitignored):

- **Config**: `config/mcporter.json` (contains the access token — **never commit this file**)
- **Project ref**: `wqasatrxqinkfaafgnli` (matches `SUPABASE_URL` in `lib/config/app_config.dart`)
- **Server name**: `supabase-instiy` (stdio, `@supabase/mcp-server-supabase@0.10.0`)

```bash
# List available tools
mcporter list supabase-instiy

# Call a tool (scalars as key=value; arrays must be JSON-encoded)
mcporter call supabase-instiy.list_tables 'project_id=wqasatrxqinkfaafgnli' 'schemas=["public"]'

# Apply a SQL migration to the hosted database
mcporter call supabase-instiy.apply_migration 'project_id=wqasatrxqinkfaafgnli' 'name=my_migration' 'query=<sql>'
```

Notes:
- v0.11.0 is a broken publish (missing dependency) — pinned to 0.10.0.
- `NPM_CONFIG_LEGACY_PEER_DEPS=false` is set in the server env because the global `~/.npmrc` sets
  `legacy-peer-deps=true`, which otherwise skips the `@modelcontextprotocol/sdk` peer dependency.
- Schema changes must ALSO be committed as versioned files under `supabase/migrations/`, and applied
  through the MCP (`apply_migration`) so the remote migration history stays in sync.

---

## Common Patterns by Package

### Supabase Flutter
- Always use `Supabase.instance.client` for client access
- RPCs return flat columns, not nested objects
- Use `.from('table').select()` pattern
- Realtime subscriptions via `.stream()`

### Riverpod
- Use `@riverpod` annotation for code generation
- Never call `notifyListeners()` in constructor
- Use `Future.microtask` + `ensureInitialized` pattern

### Shadcn UI
- Components follow shadcn/ui web patterns
- Use `Shad*` prefix for components (e.g., `ShadButton`)
- Theming via `ShadTheme` and `ShadThemeData`

### Firebase
- Initialize with `Firebase.initializeApp()`
- Use `FirebaseMessaging.instance` for push notifications
- Crashlytics via `FirebaseCrashlytics.instance`

---

## Deployment & CI/CD Protocol (TestFlight Pipeline)

Whenever the user asks to push commits, deploy, or upload a build to TestFlight:

### Core Rule: Public During Pipeline, Private Immediately After
Because macOS GitHub Actions runners require public repository visibility for free workflow execution, agents **must** follow this strict protocol whenever pushing commits or triggering the iOS TestFlight pipeline:

1. **Switch Repository to Public**:
   Before pushing or triggering the build pipeline, change repository visibility to `public`:
   ```bash
   echo "y" | gh repo edit sthashixi-netwanderer/instiy-app --visibility public
   ```
   Verify visibility:
   ```bash
   gh repo view sthashixi-netwanderer/instiy-app --json visibility
   ```

2. **Push Commit / Trigger Workflow**:
   Push changes to the `instiy` branch (which automatically triggers `.github/workflows/ios.yml`):
   ```bash
   git push origin instiy
   ```
   *(If triggering without a new commit, run `gh workflow run ios.yml --ref instiy`)*

3. **Monitor & Watch the Pipeline**:
   Find the active workflow run:
   ```bash
   gh run list --workflow=ios.yml --limit 1
   ```
   Watch the pipeline until completion (test, build, code signing, and TestFlight upload):
   ```bash
   gh run watch <run-id>
   ```

4. **Revert Repository to Private (Mandatory)**:
   **Immediately** after the pipeline finishes (whether it succeeded or failed), revert the repository visibility back to `private`:
   ```bash
   echo "y" | gh repo edit sthashixi-netwanderer/instiy-app --visibility private
   ```
   Verify visibility is restored to `PRIVATE`:
   ```bash
   gh repo view sthashixi-netwanderer/instiy-app --json visibility
   ```

5. **Report to User**:
   Report the pipeline outcome (TestFlight upload status) and confirm that the repository has been safely returned to `private`.

---

## Version Compatibility Notes

- Flutter SDK: ^3.12.0
- Dart SDK: ^3.12.0
- Node.js: Check `.nvmrc` or project config
- TypeScript: ~6.0.2 (admin panel)

---

*Last updated: 2026-09-02*
*This file should be updated when packages are added, removed, or significantly upgraded.*
