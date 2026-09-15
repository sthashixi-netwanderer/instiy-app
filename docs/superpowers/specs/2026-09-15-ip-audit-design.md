# IP Audit — Design Spec

Date: 2026-09-15
Status: Approved design (brainstorming complete), pending implementation plan

## Purpose

Give admins a page in the Instiy admin panel to audit the public IP addresses
that use the app: which devices they belong to, and which user accounts they
are associated with. Admins can also block an IP, which locks the app for
clients on that IP.

## Decisions (from brainstorming)

- **Capture scope:** app sessions (cold start, signed-in or not) + successful
  logins. Anonymous sessions produce events with no associated account.
- **IP source:** the Cloudflare worker (`api.instiy.com`) reads
  `CF-Connecting-IP`. The client never reports its own IP.
- **Device detail:** full hardware model via `device_info_plus` + app version
  via `package_info_plus` (both new Flutter deps).
- **Enforcement:** cooperative + worker-enforced blocking. The app asks the
  worker "am I blocked?" on launch and login and shows a lockout screen; all
  worker endpoints under `/functions/v1/*` (except `session-audit` itself)
  reject blocked IPs server-side. Known limit: a modified client on a blocked
  IP could still reach Supabase directly; normal users and all privileged
  worker operations are fully blocked.
- **Country data:** Cloudflare's `request.cf.country` at capture time.
  Evaluated `ip_whoer` (npm) and rejected it for this feature: `getIpInfo()`
  is a zero-argument *self-lookup* — called from the worker it would report
  Cloudflare's egress IP, and from the admin browser the admin's own IP, so
  it cannot attribute country to the audited user. (Its `package.json` also
  lists itself as a dependency, which breaks installing it as a dep.) If
  city/region/ISP detail is wanted later, the path is extending `ip_whoer`
  with an optional target-IP argument (whoer.to's `ip2co?ip=` endpoint it
  already calls supports this) behind a cached worker endpoint.

## Non-goals

- Proxying all app→Supabase traffic through the worker (full server-side
  enforcement).
- Geolocation beyond Cloudflare's free `request.cf.country`.
- Reverse lookup ("IPs used by this account") from the Users page — follow-up.
- Blocking ranges/subnets; single IPs only (`inet` stored, `/32` semantics).

## Architecture

### 1. Database — one migration `supabase/migrations/20260915120000_ip_audit.sql`

Applied via the Supabase MCP (`apply_migration`) and committed as a versioned
file, per project rules.

```sql
CREATE TABLE public.ip_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ip_address inet NOT NULL,
  user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  event_type text NOT NULL CHECK (event_type IN ('session','login')),
  user_agent text,
  platform text,          -- android | ios | web
  os_version text,
  device_model text,      -- "Pixel 7", "iPhone14,3"
  app_version text,
  country text,           -- ISO code from request.cf.country
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX ip_events_ip_created_idx ON public.ip_events (ip_address, created_at DESC);
CREATE INDEX ip_events_user_created_idx ON public.ip_events (user_id, created_at DESC);
CREATE INDEX ip_events_created_idx ON public.ip_events (created_at DESC);

CREATE TABLE public.blocked_ips (
  ip_address inet PRIMARY KEY,
  reason text NOT NULL DEFAULT '',
  blocked_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

RLS (enabled on both tables):

- `ip_events`: SELECT for admins via `public.is_admin(auth.uid())`. No INSERT /
  UPDATE / DELETE policies — only the worker writes, using the service-role
  key which bypasses RLS.
- `blocked_ips`: ALL operations for admins via `is_admin(auth.uid())`.

RPCs — `LANGUAGE plpgsql SECURITY DEFINER`, each beginning with
`IF NOT public.is_admin(auth.uid()) THEN RAISE EXCEPTION 'not_admin'; END IF;`,
and locked down with
`REVOKE ALL ON FUNCTION ... FROM PUBLIC, anon;` (the codebase already uses
this revoke pattern on `product_views` functions). Unlike
`get_unread_report_count` (a benign count with no internal gate), these RPCs
expose IP↔account linkage and must refuse non-admins even though EXECUTE is
what RLS would otherwise not cover on security-definer functions:

- `get_ip_audit_summary(p_offset int, p_limit int, p_search text)` → one row
  per IP: `ip_address, country, event_count, login_count, account_count,
  first_seen, last_seen, platforms[], device_models[], user_ids[], is_blocked,
  block_reason`. Grouped by IP, ordered by `last_seen desc`. `p_search`
  matches IP substring (`host(ip_address) ilike`) OR any associated user's
  email/full_name. Joins `blocked_ips` for the block columns.
- `get_ip_audit_count(p_search text)` → total matching IPs, for pagination.

Retention: enable `pg_cron` and schedule a daily job deleting `ip_events`
older than 180 days.

### 2. Worker — `instiy-workers`

**New handler `src/handlers/ip-audit.ts`** exposing
`POST /functions/v1/session-audit`:

- Body: `{ eventType: 'session'|'login', platform, osVersion, deviceModel,
  appVersion }` (all strings, optional except `eventType`).
- Identity: existing `verifyAuth` middleware — a valid Supabase JWT yields
  `user_id`; anonymous requests (anon key or no token) record `user_id = null`.
- IP: `CF-Connecting-IP`. Country: `request.cf?.country`. User-agent:
  `User-Agent` header. These are server-derived; client-supplied values are
  ignored.
- Dedup: skip the insert if an identical `(ip_address, user_id, event_type,
  user_agent)` event exists within the last 6 hours.
- Writes `ip_events` via service-role key.
- Always responds `200 { ip, blocked, reason, country }` so the caller learns
  its status even when the insert is deduped. Errors respond 5xx with JSON.

**New middleware `src/middleware/ip-block.ts`:** `isIpBlocked(request, env)` —
checks `blocked_ips` via service role, cached in worker memory for 60 seconds
per IP. Wired into `src/index.ts`: applied to every `/functions/v1/*` route
**except** `session-audit` (blocked clients must still learn they are
blocked) — blocked requests short-circuit with
`403 { "error": "ip_blocked", "reason": ... }`. Public share/deep-link routes
(top-level `/product/...`, `/.well-known/...`, `/referral`) are outside
`/functions/v1/*` and remain reachable, since they are opened by third
parties.

### 3. Flutter app

**New deps:** `device_info_plus`, `package_info_plus` (add to `pubspec.yaml`;
document both in `AGENTS.md` package table per project rules).

**New service `lib/services/ip_audit_service.dart`:**

- `Future<IpAuditStatus> record({required String eventType})` — collects
  device info once and caches it, then calls
  `SupabaseService.callFunction('session-audit', body: ...)` (existing helper
  sends the user JWT when signed in, anon key otherwise). Returns
  `{ip, blocked, reason}`. Never throws — all failures are swallowed (audit
  must not break the app).

**Call sites:**

- Cold start: after Supabase init, post-first-frame, fire-and-forget.
- Successful login: password sign-in, Google OAuth completion, and ID-token
  sign-in paths.

**Blocked response → `BlockedIpScreen`:** replaces the current route (not a
push, so there is no way back), signs the session out locally, shows the
block reason and a contact-support hint. Reached via the existing navigator
key / `NavigationService`.

### 4. Admin panel — `instiy-admin`

**Routing:** `<Route path="/ip-audit" element={<IpAudit />} />` plus a
sidebar nav item "IP Audit" (lucide `Globe` icon) in `App.tsx`.

**New page `src/pages/IpAudit.tsx`** (follows existing page patterns,
radix `dialog.tsx` for modals):

- Stat cards: unique IPs (matching current search), events in the last 7
  days, blocked IP count.
- Main table (rows from `get_ip_audit_summary`, paginated 25/page with
  prev/next using `get_ip_audit_count`): IP + country, platform chips,
  associated accounts (count + up-to-3 avatar stack), event count, first/last
  seen, blocked badge, block/unblock action.
- Search box (debounced) feeding `p_search`.
- Row click opens the **IP details modal**:
  - *Header:* IP, country, blocked badge, Block/Unblock button.
  - *Device section:* distinct device models, platforms, OS versions, app
    versions, and stored user-agents parsed into browser/OS chips with a
    hand-rolled parser (no new dependency).
  - *Activity section:* latest ~50 events for the IP (type badge
    session/login, device model, platform, time-ago).
  - *Accounts section:* all accounts seen on this IP — avatar, name, email,
    university, suspended/admin badges, "View in Users" link.
- **Block dialog:** required reason text; warning banner showing the number
  of accounts and events seen from this IP ("campus networks often share one
  public IP"). Inserts into `blocked_ips`. **Unblock** is a confirm-only
  dialog (delete from `blocked_ips`).
- **Users deep link:** `Users.tsx` initializes its existing `searchQuery`
  state from a `?q=` URL param so "View in Users" can pre-fill the account
  search.

## Data flow

```
App cold start ─┐
Login success ──┴─► POST api.instiy.com/functions/v1/session-audit
                       │ JWT (optional) → user_id
                       │ CF-Connecting-IP → ip, request.cf.country → country
                       │ User-Agent header → user_agent
                       │ device payload from app → platform/model/os/app version
                       ├─ dedup (6h window) then INSERT ip_events (service role)
                       └─ 200 { ip, blocked, reason, country }
                              │
              blocked = true ─┴─► BlockedIpScreen + local sign-out

Admin panel ─► get_ip_audit_summary / get_ip_audit_count ─► IpAudit page
            ─► ip_events (filtered by ip) ────────────────► modal details
            ─► blocked_ips insert/delete ─────────────────► block / unblock
```

## Error handling

- App: any worker failure or timeout is swallowed; no user-visible effect
  other than the event not being recorded.
- Worker: invalid body → 400; unknown errors → 500 JSON. The block check
  fails open (worker unavailable ⇒ requests proceed) except where the
  blocklist cache already holds the IP.
- Admin RPCs raise `not_admin` for non-admin callers (explicit gate inside
  each function, see Database); the panel shows the error state like other
  pages do.

## Testing / verification

- Migration: applied through Supabase MCP; RLS verified with anon vs admin
  sessions.
- Worker: `wrangler dev` + curl — record, dedup within 6h, anonymous vs
  authenticated event, 403 on blocked IP for e.g. `get-secrets`.
- Admin: `npm run build` (tsc) passes; manual pass over page/modal/dialogs.
- App: `flutter analyze` clean; emulator run shows a `session` row, login
  adds a `login` row; blocking the emulator's IP (via WiFi hotspot or direct
  egress IP) triggers the lockout on next launch.
- AGENTS.md updated with the two new packages.

## Privacy

Only session/login events are recorded — no browsing behavior. IP + device +
account linkage is personal data; retention is bounded at 180 days by the
cron job. Access is admin-only via RLS.
