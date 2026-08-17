# Instiy Security Audit Report

**Date:** 2026-06-13  
**Scope:** Full `lib/` codebase scan  
**Status:** All issues fixed in this commit

---

## Vulnerabilities Found & Fixed

### 1. CRITICAL — Hardcoded Secrets in `SecretsService` (Default Fallbacks)
**File:** `lib/services/secrets_service.dart`  
**Risk:** R2 access key ID, Paystack test key, and Giphy API key are hardcoded as default fallbacks. If the remote fetch fails, these real credentials are used and are visible in the compiled binary.  
**Fix:** Replaced all sensitive hardcoded defaults with empty strings. Code paths that need secrets now call `ensureLoaded()` and fail gracefully if secrets are unavailable.

---

### 2. HIGH — URL Injection via Carousel Slide `buttonLinkValue`
**File:** `lib/screens/home/home_screen.dart`  
**Risk:** `launchUrl(Uri.parse(slide.buttonLinkValue!))` launches any URL stored in the database without scheme validation. A compromised DB record could launch `javascript:`, `file://`, or `intent://` URIs.  
**Fix:** Added scheme allowlist (`https`, `http`) before calling `launchUrl`. Non-http(s) URLs are silently dropped.

---

### 3. HIGH — URL Injection in Map Preview / Google Maps Launch
**File:** `lib/screens/seller/business_profile_screen.dart`  
**Risk:** `_openMapPreview` and `_openInGoogleMaps` call `launchUrl(Uri.parse(url))` on a URL stored in the database (`location_url` field) without any scheme validation.  
**Fix:** Added `https`/`http` scheme guard before launching.

---

### 4. HIGH — GPS Address Lookup URL Injection
**File:** `lib/screens/seller/edit_business_profile_screen.dart`  
**Risk:** `_gpsApiUrl` is fetched from the `ghanapost_config` table and used directly in `Uri.parse('$url?address=$address')`. A malicious admin could set this to an attacker-controlled URL, exfiltrating the GPS API token.  
**Fix:** Validate that `_gpsApiUrl` starts with `https://` before using it. Fall back to the known-good default URL if validation fails.

---

### 5. MEDIUM — `unawaited` `launchUrl` in Home Screen
**File:** `lib/screens/home/home_screen.dart`  
**Risk:** `launchUrl(...)` is called without `await` or error handling. Failures are silently swallowed and the lint rule `unawaited_futures` would flag this.  
**Fix:** Wrapped in `unawaited(...)` with a try/catch, consistent with the rest of the codebase.

---

### 6. MEDIUM — `BuildContext` Used Across `await` Without `mounted` Check
**File:** `lib/screens/seller/business_profile_screen.dart` (`_callNumber`, `_openWhatsApp`)  
**Risk:** Both methods `await launchUrl(...)` and then implicitly use `context` (via `debugPrint` and the outer widget tree). If the widget is disposed during the await, this is a use-after-free of the context.  
**Fix:** Added `if (!mounted) return;` guards after each `await`.

---

### 7. MEDIUM — Missing `mounted` Check After `await` in `_handleCarouselButtonTap`
**File:** `lib/screens/home/home_screen.dart`  
**Risk:** No `mounted` check after the async `launchUrl` call.  
**Fix:** Added `mounted` guard.

---

### 8. LOW — Notification ID Collision via `millisecondsSinceEpoch ~/ 1000`
**File:** `lib/services/local_notification_service.dart`  
**Risk:** Multiple notification helpers use `DateTime.now().millisecondsSinceEpoch ~/ 1000` as the notification ID. Two notifications fired within the same second will overwrite each other.  
**Fix:** Changed to `millisecondsSinceEpoch % 2147483647` (full millisecond precision, capped to int32 max) to minimize collisions.

---

### 9. LOW — Error Message Leaks Internal Exception Details to UI
**File:** `lib/screens/seller/edit_business_profile_screen.dart`  
**Risk:** `ShadToast(title: Text('Lookup failed: $e'))` exposes raw exception messages (including stack traces or internal API error bodies) to the user.  
**Fix:** Show a generic user-friendly message; log the full error via `debugPrint`.

---

### 10. OPTIMIZATION — `SecretsService` Default Fallbacks Removed
Removing hardcoded secrets also improves security posture: the app will not silently use stale test credentials in production if the remote fetch fails.

---

## Performance Optimizations Applied

- **`_lookupAddress`**: Added early return if `_gpsApiUrl` fails validation, preventing a network call to an untrusted URL.
- **Notification IDs**: Higher-precision IDs reduce silent notification drops.
- **URL scheme validation**: Short-circuits before any I/O for invalid URLs.
