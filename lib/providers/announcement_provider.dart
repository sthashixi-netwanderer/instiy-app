import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/announcement_service.dart';
import '../services/supabase_service.dart';

/// Reactive home of the active announcements.
///
/// The list loads once per app run, then stays fresh two ways:
///  • a Supabase realtime subscription on `app_announcements` refetches on
///    any admin change (create, edit, pause, delete), and
///  • [ensureLoaded] refetches when older than [_staleTtl] as a fallback
///    for missed realtime events.
///
/// Screens/dialogs read [announcementProvider]; [AnnouncementObserver]
/// awaits [ensureLoaded] on each navigation before deciding to pop a dialog.
class AnnouncementNotifier extends Notifier<List<AppAnnouncement>> {
  static const _staleTtl = Duration(minutes: 5);

  RealtimeChannel? _channel;
  Future<void>? _inFlight;
  DateTime _lastFetched = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hasLoaded = false;

  @override
  List<AppAnnouncement> build() {
    ref.onDispose(() {
      _channel?.unsubscribe();
      _channel = null;
    });
    unawaited(ensureLoaded());
    _subscribeToChanges();
    return const [];
  }

  /// Loads announcements if they haven't been loaded yet or are stale.
  /// Concurrent calls share one in-flight request.
  Future<void> ensureLoaded({bool force = false}) {
    if (_inFlight != null) return _inFlight!;
    if (!force &&
        _hasLoaded &&
        DateTime.now().difference(_lastFetched) < _staleTtl) {
      return Future.value();
    }
    final future = _fetch();
    _inFlight = future;
    return future;
  }

  Future<void> _fetch() async {
    try {
      final list = await AnnouncementService.fetchAnnouncements();
      if (state.isNotEmpty || list.isNotEmpty) state = list;
      _hasLoaded = true;
      _lastFetched = DateTime.now();
    } catch (e) {
      // Fail soft — no popups on network errors; retry on next navigation.
      debugPrint('Announcement refresh failed: $e');
    } finally {
      _inFlight = null;
    }
  }

  void _subscribeToChanges() {
    if (_channel != null) return;
    _channel = SupabaseService.client
        .channel('app-announcements')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'app_announcements',
          callback: (_) => unawaited(ensureLoaded(force: true)),
        )
        .subscribe();
  }
}

final announcementProvider =
    NotifierProvider<AnnouncementNotifier, List<AppAnnouncement>>(
  AnnouncementNotifier.new,
);
