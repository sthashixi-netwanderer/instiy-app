import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/business_profile_model.dart';
import '../models/seller_review_model.dart';
import '../models/product_model.dart';
import '../services/business_profile_service.dart';
import '../services/follow_service.dart';
import '../services/supabase_service.dart';
import '../providers/block_provider.dart';

class BusinessProfileProvider extends ChangeNotifier {
  BusinessProfile? _profile;
  StoreStats? _stats;
  List<ProductReview> _reviews = [];
  List<Product> _products = [];
  bool _isFollowing = false;
  bool _isSellerVerified = false;
  bool _isLoading = false;
  bool _isLoadingReviews = false;
  final bool _isLoadingProducts = false;
  bool _hasMoreReviews = true;
  int _reviewOffset = 0;
  static const int _reviewLimit = 20;
  String? _error;

  RealtimeChannel? _followsChannel;
  RealtimeChannel? _reviewsChannel;
  RealtimeChannel? _reviewRepliesChannel;

  BusinessProfile? get profile => _profile;
  StoreStats? get stats => _stats;
  List<ProductReview> get reviews => _reviews;
  List<Product> get products => _products;
  bool get isFollowing => _isFollowing;
  bool get isSellerVerified => _isSellerVerified;
  bool get isLoading => _isLoading;
  bool get isLoadingReviews => _isLoadingReviews;
  bool get isLoadingProducts => _isLoadingProducts;
  bool get hasMoreReviews => _hasMoreReviews;
  String? get error => _error;

  Future<void> loadStore(String sellerId) async {
    if (BlockProvider.instance.isUserBlocked(sellerId)) {
      _isLoading = false;
      _error = 'This profile is unavailable.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Load profile, stats, following status, products, and verification status in parallel
      final results = await Future.wait([
        BusinessProfileService.getProfile(sellerId),
        BusinessProfileService.getStoreStats(sellerId),
        BusinessProfileService.isFollowing(sellerId),
        BusinessProfileService.getStoreProducts(sellerId),
        BusinessProfileService.getSellerVerificationStatus(sellerId),
      ]);

      _profile = results[0] as BusinessProfile?;
      _stats = results[1] as StoreStats;
      _isFollowing = results[2] as bool;
      final blockProv = BlockProvider.instance;
      _products = blockProv.filterProducts(results[3] as List<Product>);
      _isSellerVerified = results[4] as bool;

      // Load first page of reviews
      _reviews = [];
      _reviewOffset = 0;
      _hasMoreReviews = true;
      await _loadReviews(sellerId);

      _subscribeToRealtime(sellerId);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadReviews(String sellerId) async {
    if (!_hasMoreReviews) return;

    _isLoadingReviews = true;
    notifyListeners();

    try {
      final newReviews = await BusinessProfileService.getStoreReviews(
        sellerId: sellerId,
        offset: _reviewOffset,
        limit: _reviewLimit,
      );

      if (newReviews.length < _reviewLimit) {
        _hasMoreReviews = false;
      }

      _reviews.addAll(BlockProvider.instance.filterReviews(newReviews));
      _reviewOffset += newReviews.length;
    } catch (_) {}

    _isLoadingReviews = false;
    notifyListeners();
  }

  Future<void> loadMoreReviews(String sellerId) async {
    if (_isLoadingReviews || !_hasMoreReviews) return;
    await _loadReviews(sellerId);
  }

  Future<void> reloadReviews(String sellerId) async {
    await _silentReloadReviews(sellerId);
  }

  Future<void> toggleFollow(String sellerId) async {
    final currentUserId = SupabaseService.auth.currentUser?.id;
    if (currentUserId == null || currentUserId == sellerId) return;

    try {
      if (_isFollowing) {
        await FollowService.unfollow(sellerId);
        _isFollowing = false;
        if (_stats != null) {
          _stats = StoreStats(
            followerCount: _stats!.followerCount - 1,
            reviewCount: _stats!.reviewCount,
            averageRating: _stats!.averageRating,
            totalProducts: _stats!.totalProducts,
          );
        }
      } else {
        await FollowService.follow(sellerId);
        _isFollowing = true;
        if (_stats != null) {
          _stats = StoreStats(
            followerCount: _stats!.followerCount + 1,
            reviewCount: _stats!.reviewCount,
            averageRating: _stats!.averageRating,
            totalProducts: _stats!.totalProducts,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void _subscribeToRealtime(String sellerId) {
    _unsubscribeFromRealtime();

    _followsChannel = SupabaseService.client
        .channel('store-follows:$sellerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'seller_follows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'seller_id',
            value: sellerId,
          ),
          callback: (_) async {
            try {
              _stats = await BusinessProfileService.getStoreStats(sellerId);
              _isFollowing = await BusinessProfileService.isFollowing(sellerId);
              notifyListeners();
            } catch (_) {}
          },
        );
    _followsChannel!.subscribe();

    _reviewsChannel = SupabaseService.client
        .channel('store-reviews:$sellerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product_reviews',
          callback: (_) async {
            await _silentReloadReviews(sellerId);
          },
        );
    _reviewsChannel!.subscribe();

    _reviewRepliesChannel = SupabaseService.client
        .channel('store-review-replies:$sellerId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product_review_replies',
          callback: (_) async {
            await _silentReloadReviews(sellerId);
          },
        );
    _reviewRepliesChannel!.subscribe();
  }

  Future<void> _silentReloadReviews(String sellerId) async {
    try {
      _reviews = [];
      _reviewOffset = 0;
      _hasMoreReviews = true;
      final newReviews = await BusinessProfileService.getStoreReviews(
        sellerId: sellerId,
        offset: 0,
        limit: _reviewLimit,
      );
      _reviews = newReviews;
      _reviewOffset = newReviews.length;
      if (newReviews.length < _reviewLimit) _hasMoreReviews = false;
      notifyListeners();
    } catch (_) {}
  }

  void _unsubscribeFromRealtime() {
    final channels = [_followsChannel, _reviewsChannel, _reviewRepliesChannel];
    for (final ch in channels) {
      if (ch != null) SupabaseService.client.removeChannel(ch);
    }
    _followsChannel = null;
    _reviewsChannel = null;
    _reviewRepliesChannel = null;
  }

  void clear() {
    _profile = null;
    _stats = null;
    _reviews = [];
    _products = [];
    _isFollowing = false;
    _isSellerVerified = false;
    _hasMoreReviews = true;
    _reviewOffset = 0;
    _error = null;
    _unsubscribeFromRealtime();
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
