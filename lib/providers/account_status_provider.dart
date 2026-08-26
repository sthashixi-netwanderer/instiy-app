import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/navigation_service.dart';
import '../services/supabase_service.dart';
import 'providers.dart';

/// Live suspension status of the signed-in user.
///
/// Owns the single Realtime subscription on the user's own row in `users` so
/// the whole app reacts no matter which screen is open:
///  • admin flips `suspended` to true  — the app jumps to /suspended. The
///    session is deliberately kept alive so the user can still submit a
///    complaint from the suspended screen and so the reinstatement event can
///    reach us,
///  • admin flips `suspended` to false — the profile is refreshed and the app
///    returns to /home.
///
/// [AuthProvider] keeps its own `_isSuspended` flag in sync by listening to
/// this provider, so splash/login gating continues to work unchanged.
class AccountStatusNotifier extends Notifier<bool> {
  RealtimeChannel? _channel;
  String? _watchedUserId;

  @override
  bool build() {
    ref.onDispose(_removeChannel);
    return false;
  }

  /// Start (or stop, when [userId] is null) watching the given user.
  ///
  /// [suspended] seeds the current status without triggering navigation —
  /// the startup/login flows show the suspended screen themselves.
  void watchUser(String? userId, {bool suspended = false}) {
    // Same user — keep the existing channel and just resync the flag.
    if (userId == _watchedUserId) {
      if (suspended != state) state = suspended;
      return;
    }

    _watchedUserId = userId;
    _removeChannel();
    state = suspended;

    if (userId == null) return;

    _channel = SupabaseService.client
        .channel('account-status:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) =>
              unawaited(_onUserRowChanged(payload.newRecord)),
        )
        .subscribe();
  }

  /// Marks the user suspended from an out-of-band detection (the app-resume
  /// re-check) and performs the same navigation as the realtime path.
  void markSuspended() {
    if (state) return;
    state = true;
    _navigateTo('/suspended');
  }

  Future<void> _onUserRowChanged(Map<String, dynamic> newRecord) async {
    final suspended = newRecord['suspended'] == true;

    if (suspended && !state) {
      state = true;
      _navigateTo('/suspended');
    } else if (!suspended && state) {
      state = false;
      // Refresh the in-memory profile so the rest of the app sees the lifted
      // suspension without a full reload. _syncAccountStatus keeps the
      // realtime watcher pointed at the same row.
      await ref.read(authProvider).refreshOnReinstate();
      _navigateTo('/home');
    }
  }

  void _navigateTo(String route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavigationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
        route,
        (route) => false,
      );
    });
  }

  void _removeChannel() {
    if (_channel != null) {
      SupabaseService.client.removeChannel(_channel!);
      _channel = null;
    }
  }
}

final accountStatusProvider =
    NotifierProvider<AccountStatusNotifier, bool>(AccountStatusNotifier.new);
