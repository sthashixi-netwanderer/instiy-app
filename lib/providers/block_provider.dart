import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/seller_review_model.dart';
import '../models/message_model.dart';
import '../services/block_service.dart';
import '../services/supabase_service.dart';

class _FallbackBlockProvider extends BlockProvider {
  @override
  bool isUserBlocked(String userId) => false;

  @override
  List<Product> filterProducts(List<Product> products) => products;

  @override
  List<ProductReview> filterReviews(List<ProductReview> reviews) => reviews;

  @override
  List<Conversation> filterConversations(List<Conversation> conversations) =>
      conversations;
}

class BlockProvider extends ChangeNotifier {
  static BlockProvider? _instance;
  static BlockProvider get instance => _instance ?? _FallbackBlockProvider();

  Set<String> _blockedIds = {};
  bool _initialized = false;
  RealtimeChannel? _channel;

  Set<String> get blockedIds => _blockedIds;

  BlockProvider() {
    _instance = this;
  }

  bool isUserBlocked(String userId) => _blockedIds.contains(userId);

  List<Product> filterProducts(List<Product> products) {
    if (_blockedIds.isEmpty) return products;
    return products.where((p) => !_blockedIds.contains(p.sellerId)).toList();
  }

  List<ProductReview> filterReviews(List<ProductReview> reviews) {
    if (_blockedIds.isEmpty) return reviews;
    return reviews.where((r) => !_blockedIds.contains(r.reviewerId)).toList();
  }

  List<Conversation> filterConversations(List<Conversation> conversations) {
    if (_blockedIds.isEmpty) return conversations;
    return conversations.where((c) => !_blockedIds.contains(c.otherUserId)).toList();
  }

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
