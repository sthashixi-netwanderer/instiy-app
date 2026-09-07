import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/seller_review_model.dart';
import '../models/order_model.dart';
import '../services/seller_service.dart';
import '../services/supabase_service.dart';
import '../services/local_notification_service.dart';
import '../services/email_service.dart';

class SellerProvider extends ChangeNotifier {
  DashboardStats? _dashboardStats;
  List<ProductReview> _reviews = [];
  List<Order> _sellerOrders = [];
  Map<String, dynamic>? _analytics;
  bool _isLoading = false;
  bool _isLoadingMoreReviews = false;
  bool _hasMoreReviews = true;
  String? _error;
  bool _initialized = false;

  RealtimeChannel? _productsChannel;
  RealtimeChannel? _reviewsChannel;
  RealtimeChannel? _reviewRepliesChannel;
  RealtimeChannel? _followsChannel;
  RealtimeChannel? _ordersChannel;

  DashboardStats? get dashboardStats => _dashboardStats;
  List<ProductReview> get reviews => _reviews;
  List<Order> get sellerOrders => _sellerOrders;
  Map<String, dynamic>? get analytics => _analytics;
  bool get isLoading => _isLoading;
  bool get isLoadingMoreReviews => _isLoadingMoreReviews;
  bool get hasMoreReviews => _hasMoreReviews;
  String? get error => _error;

  String? _currentUserId;

  SellerProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        final userId = session.user.id;
        if (_currentUserId == userId) return;
        _currentUserId = userId;
        _subscribeToRealtime(userId);
      } else {
        _unsubscribeFromRealtime();
        _dashboardStats = null;
        _reviews = [];
        _sellerOrders = [];
        _analytics = null;
        _error = null;
        _currentUserId = null;
        _initialized = false;
        notifyListeners();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      _subscribeToRealtime(currentUser.id);
    }
  }

  void _subscribeToRealtime(String userId) {
    _unsubscribeFromRealtime();

    _productsChannel = SupabaseService.client
        .channel('seller-products:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'seller_id',
            value: userId,
          ),
          callback: (_) {
            _silentReloadStats(userId);
          },
        );
    _productsChannel!.subscribe();

    _reviewsChannel = SupabaseService.client
        .channel('seller-reviews:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product_reviews',
          callback: (_) {
            _silentReloadStats(userId);
            _silentReloadReviews(userId);
          },
        );
    _reviewsChannel!.subscribe();

    _reviewRepliesChannel = SupabaseService.client
        .channel('seller-review-replies:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'product_review_replies',
          callback: (_) {
            _silentReloadReviews(userId);
          },
        );
    _reviewRepliesChannel!.subscribe();

    _followsChannel = SupabaseService.client
        .channel('seller-follows:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'seller_follows',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'seller_id',
            value: userId,
          ),
          callback: (_) {
            _silentReloadStats(userId);
          },
        );
    _followsChannel!.subscribe();

    _ordersChannel = SupabaseService.client
        .channel('seller-orders:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) {
            _silentReloadStats(userId);
            _silentReloadAnalytics(userId);
            _silentReloadSellerOrders(userId);
          },
        );
    _ordersChannel!.subscribe();

    ensureInitialized(userId);
  }

  void _unsubscribeFromRealtime() {
    final channels = [
      _productsChannel,
      _reviewsChannel,
      _reviewRepliesChannel,
      _followsChannel,
      _ordersChannel,
    ];
    for (final ch in channels) {
      if (ch != null) {
        SupabaseService.client.removeChannel(ch);
      }
    }
    _productsChannel = null;
    _reviewsChannel = null;
    _reviewRepliesChannel = null;
    _followsChannel = null;
    _ordersChannel = null;
  }

  Future<void> _silentReloadStats(String userId) async {
    try {
      _dashboardStats = await SellerService.getDashboardStats(userId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _silentReloadReviews(String userId) async {
    try {
      _reviews = await SellerService.getProductReviews(userId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _silentReloadAnalytics(String userId) async {
    try {
      _analytics = await SellerService.getAnalytics(userId);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _silentReloadSellerOrders(String userId) async {
    try {
      _sellerOrders = await SellerService.getSellerOrders(userId);
      notifyListeners();
    } catch (_) {}
  }

  bool get isInitialized => _initialized;

  Future<void> ensureInitialized(String userId, {bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;

    final silent = _dashboardStats != null;
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final results = await Future.wait([
        SellerService.getDashboardStats(userId),
        SellerService.getProductReviews(userId, offset: 0, limit: 20),
        SellerService.getAnalytics(userId),
        SellerService.getSellerOrders(userId),
      ]);
      _dashboardStats = results[0] as DashboardStats?;
      _reviews = List<ProductReview>.from(results[1] as Iterable);
      _hasMoreReviews = _reviews.length >= 20;
      _analytics = results[2] as Map<String, dynamic>?;
      _sellerOrders = List<Order>.from(results[3] as Iterable);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadDashboardStats(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _dashboardStats = await SellerService.getDashboardStats(userId);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadReviews(String userId) async {
    _isLoading = true;
    _hasMoreReviews = true;
    notifyListeners();

    try {
      _reviews = await SellerService.getProductReviews(userId, offset: 0, limit: 20);
      _hasMoreReviews = _reviews.length >= 20;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMoreReviews(String userId) async {
    if (_isLoadingMoreReviews || !_hasMoreReviews) return;

    _isLoadingMoreReviews = true;
    notifyListeners();

    try {
      final more = await SellerService.getProductReviews(userId, offset: _reviews.length, limit: 20);
      _reviews.addAll(more);
      _hasMoreReviews = more.length >= 20;
    } catch (e) {
      // Silently fail on load-more
    }

    _isLoadingMoreReviews = false;
    notifyListeners();
  }

  Future<void> replyToReview({
    required String reviewId,
    required String sellerId,
    required String reply,
    List<dynamic> mediaFiles = const [],
  }) async {
    try {
      // Get review info before replying
      final review = await SupabaseService.client
          .from('product_reviews')
          .select('reviewer_id, product_id')
          .eq('id', reviewId)
          .maybeSingle();

      await SellerService.replyToReview(
        reviewId: reviewId,
        sellerId: sellerId,
        reply: reply,
        mediaFiles: mediaFiles,
      );

      // Send email to reviewer
      if (review != null) {
        final reviewer = await SupabaseService.client
            .from('users')
            .select('full_name, email')
            .eq('id', review['reviewer_id'])
            .maybeSingle();

        final seller = await SupabaseService.client
            .from('users')
            .select('full_name')
            .eq('id', sellerId)
            .maybeSingle();

        final product = await SupabaseService.client
            .from('products')
            .select('title')
            .eq('id', review['product_id'])
            .maybeSingle();

        if (reviewer != null && seller != null && product != null) {
          // In-app notification for the reviewer
          await SupabaseService.table('notifications').insert({
            'user_id': review['reviewer_id'],
            'title': 'Seller replied to your review',
            'body': '${seller['full_name'] as String? ?? 'The seller'} replied to your review on "${product['title'] as String? ?? 'a product'}"',
            'type': 'review',
            'data': {
              'product_id': review['product_id'],
              'seller_id': sellerId,
            },
          });

          final reviewerEmail = reviewer['email'] as String?;
          if (reviewerEmail != null) {
            await EmailService.sendReviewReply(
              reviewerEmail: reviewerEmail,
              reviewerName: reviewer['full_name'] as String? ?? 'User',
              sellerName: seller['full_name'] as String? ?? 'Seller',
              productTitle: product['title'] as String? ?? 'Product',
              reply: reply,
            );
          }
        }
      }

      await loadReviews(sellerId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadSellerOrders(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _sellerOrders = await SellerService.getSellerOrders(userId);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _notifyDeliverySuccess({
    required String? orderItemId,
    required num? amount,
  }) async {
    if (orderItemId == null) return;
    try {
      final orderItem = await SupabaseService.client
          .from('order_items')
          .select('order_id, product_title')
          .eq('id', orderItemId)
          .maybeSingle();

      if (orderItem != null) {
        final order = await SupabaseService.client
            .from('orders')
            .select('buyer_id, delivery_fee, delivery_mode')
            .eq('id', orderItem['order_id'])
            .maybeSingle();

        if (order != null) {
          final buyer = await SupabaseService.client
              .from('users')
              .select('full_name, email')
              .eq('id', order['buyer_id'])
              .maybeSingle();

          final seller = await SupabaseService.client
              .from('users')
              .select('full_name')
              .eq('id', SupabaseService.auth.currentUser?.id ?? '')
              .maybeSingle();

          if (buyer != null && seller != null) {
            final buyerEmail = buyer['email'] as String?;
            final buyerName = buyer['full_name'] as String? ?? 'Buyer';
            final sellerName = seller['full_name'] as String? ?? 'Seller';
            final productTitle = orderItem['product_title'] as String? ?? 'Product';
            final deliveryFee = order['delivery_mode'] == 'delivery'
                ? (order['delivery_fee'] as num?)?.toDouble() ?? 0.0
                : 0.0;

            await LocalNotificationService.notifyDeliveryApproved(
              productTitle: productTitle,
              amount: amount?.toDouble() ?? 0,
              deliveryFee: deliveryFee,
            );

            if (buyerEmail != null) {
              await EmailService.sendDeliveryConfirmed(
                buyerEmail: buyerEmail,
                buyerName: buyerName,
                sellerName: sellerName,
                productTitle: productTitle,
                amount: amount?.toDouble() ?? 0,
              );
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> verifyDelivery(String orderItemId, String code) async {
    try {
      final result = await SellerService.verifyDelivery(orderItemId, code);
      if (result['success'] == true) {
        final amount = result['amount'] as num?;
        await _notifyDeliverySuccess(orderItemId: orderItemId, amount: amount);
      }
      return result;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> verifyDeliveryByCode(String code) async {
    try {
      final result = await SellerService.verifyDeliveryByCode(code);
      if (result['success'] == true) {
        final amount = result['amount'] as num?;
        final orderItemId = result['order_item_id'] as String? ?? result['item_id'] as String?;
        await _notifyDeliverySuccess(orderItemId: orderItemId, amount: amount);
      }
      return result;
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<void> loadAnalytics(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _analytics = await SellerService.getAnalytics(userId);
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
