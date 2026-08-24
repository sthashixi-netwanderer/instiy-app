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

/// Announcement state lives in [AnnouncementNotifier] (Riverpod), which keeps
/// the list fresh via realtime. This service is the data layer: fetching,
/// per-user view capping (SharedPreferences) and the once-per-session show
/// guard so the popup never nags on every navigation within a single sitting.
class AnnouncementService {
  static const _viewCountPrefix = 'announcement_views_';
  static final Set<String> _shownThisSession = {};

  /// Guards against stacking dialogs when several routes fire in quick
  /// succession (e.g. deep-link chains).
  static bool dialogVisible = false;

  /// Fetches the currently active announcements from the database.
  /// Failures propagate to the caller (the provider swallows them).
  static Future<List<AppAnnouncement>> fetchAnnouncements() async {
    final rows = await SupabaseService.table('app_announcements')
        .select('id, title, content, target_screens, max_views')
        .eq('is_active', true)
        .order('created_at', ascending: false);
    return (rows as List<dynamic>)
        .map((r) => AppAnnouncement.fromJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// The announcement to show on [routeName] from [announcements], if any:
  /// it must target the screen, not have been shown this session, and be
  /// under its per-user view cap.
  static Future<AppAnnouncement?> pendingFor(
    List<AppAnnouncement> announcements,
    String routeName,
  ) async {
    if (announcements.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    for (final announcement in announcements) {
      if (!announcement.targets(routeName)) continue;
      if (_shownThisSession.contains(announcement.id)) continue;
      if ((prefs.getInt('$_viewCountPrefix${announcement.id}') ?? 0) >=
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
    final prefs = await SharedPreferences.getInstance();
    final key = '$_viewCountPrefix${announcement.id}';
    await prefs.setInt(key, (prefs.getInt(key) ?? 0) + 1);
  }
}
