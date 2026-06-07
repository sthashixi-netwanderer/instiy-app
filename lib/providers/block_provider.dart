import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/block_service.dart';
import '../services/supabase_service.dart';

class BlockProvider extends ChangeNotifier {
  Set<String> _blockedIds = {};
  bool _initialized = false;
  RealtimeChannel? _channel;

  Set<String> get blockedIds => _blockedIds;

  bool isUserBlocked(String userId) => _blockedIds.contains(userId);

  void ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _loadBlocks();
    _subscribeToRealtime();
  }

  Future<void> _loadBlocks() async {
    try {
      _blockedIds = await BlockService.getBlockedUserIds();
      notifyListeners();
    } catch (_) {}
  }

  void _subscribeToRealtime() {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) return;

    _channel = SupabaseService.client
        .channel('block-provider-${DateTime.now().millisecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'blocked_users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'blocker_id',
            value: uid,
          ),
          callback: (_) => _loadBlocks(),
        );
    _channel!.subscribe();
  }

  Future<void> blockUser(String userId) async {
    await BlockService.blockUser(userId);
    _blockedIds.add(userId);
    notifyListeners();
  }

  Future<void> unblockUser(String userId) async {
    await BlockService.unblockUser(userId);
    _blockedIds.remove(userId);
    notifyListeners();
  }

  Future<void> refresh() async {
    await _loadBlocks();
  }

  @override
  void dispose() {
    if (_channel != null) {
      SupabaseService.client.removeChannel(_channel!);
    }
    super.dispose();
  }
}
