import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// An admin-authored popup dialog shown on selected app screens.
///
/// [content] is markdown (images, links and emojis included) rendered by the
/// announcement dialog. [targetScreens] holds route names like '/home'.
/// [maxViews] caps how many times this announcement may be shown to a user —
/// the count is kept locally so it also works before sign-in.
class AppAnnouncement {
  final String id;
  final String title;
  final String content;
  final List<String> targetScreens;
  final int maxViews;

  const AppAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    required this.targetScreens,
    required this.maxViews,
  });

  factory AppAnnouncement.fromJson(Map<String, dynamic> json) {
    return AppAnnouncement(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      targetScreens: (json['target_screens'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      maxViews: (json['max_views'] as num?)?.toInt() ?? 1,
    );
  }

  bool targets(String routeName) => targetScreens.contains(routeName);
}

/// Fetches active announcements once per session and enforces the per-user
/// view cap. Showing is limited to once per announcement per app session so
/// the popup never nags on every navigation within a single sitting.
class AnnouncementService {
  static List<AppAnnouncement>? _cache;
  static final Set<String> _shownThisSession = {};

  static const _viewCountPrefix = 'announcement_views_';

  /// Loads active announcements into the in-memory cache. Safe to call
  /// repeatedly; failures fail soft (no popups on network errors).
  static Future<void> ensureLoaded({bool force = false}) async {
    if (_cache != null && !force) return;
    try {
      final rows = await SupabaseService.table('app_announcements')
          .select('id, title, content, target_screens, max_views')
          .eq('is_active', true)
          .order('created_at', ascending: false);
      _cache = (rows as List<dynamic>)
          .map((r) => AppAnnouncement.fromJson(Map<String, dynamic>.from(r)))
          .toList();
    } catch (_) {
      _cache ??= const [];
    }
  }

  /// The announcement to show on [routeName], if any: it must target the
  /// screen, not have been shown this session, and be under its view cap.
  static Future<AppAnnouncement?> pendingFor(String routeName) async {
    final cache = _cache;
    if (cache == null || cache.isEmpty) return null;
    await _loadPrefs();
    for (final announcement in cache) {
      if (!announcement.targets(routeName)) continue;
      if (_shownThisSession.contains(announcement.id)) continue;
      if ((_prefs.getInt('$_viewCountPrefix${announcement.id}') ?? 0) >=
          announcement.maxViews) {
        continue;
      }
      return announcement;
    }
    return null;
  }

  /// Marks [announcement] as shown for this session and increments its
  /// persistent view count.
  static Future<void> markShown(AppAnnouncement announcement) async {
    _shownThisSession.add(announcement.id);
    await _loadPrefs();
    final key = '$_viewCountPrefix${announcement.id}';
    await _prefs.setInt(key, (_prefs.getInt(key) ?? 0) + 1);
  }

  /// Guards against stacking dialogs when several routes fire in quick
  /// succession (e.g. deep-link chains).
  static bool dialogVisible = false;

  static late SharedPreferences _prefs;

  static Future<void> _loadPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }
}
