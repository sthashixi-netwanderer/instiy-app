import 'dart:isolate';
import 'supabase_service.dart';
import '../models/seller_review_model.dart';
import '../models/order_model.dart';

// Top-level function for isolate — parses raw JSON list into ProductReviews
List<ProductReview> _parseReviewList(List<dynamic> rawList) {
  return rawList
      .map((json) => ProductReview.fromJson(json as Map<String, dynamic>))
      .toList();
}

class SellerService {
  static Future<DashboardStats> getDashboardStats(String userId) async {
    final supabase = SupabaseService.instance;

    final productsResponse = await supabase
        .from('products')
        .select('id, status, created_at, stock_quantity')
        .eq('seller_id', userId);

    final allProducts = productsResponse as List;
    // Total quantity of all products listed
    final totalProducts = allProducts.fold<int>(0, (sum, p) => sum + ((p['stock_quantity'] as num?)?.toInt() ?? 0));
    final activeListings = allProducts.where((p) => p['status'] == 'available').length;

    final productIds = allProducts.map((p) => p['id'] as String).toList();

    double averageRating = 0;
    int newReviews = 0;

    if (productIds.isNotEmpty) {
      final sevenDaysAgo = DateTime.now().toUtc().subtract(const Duration(days: 7)).millisecondsSinceEpoch;

      final reviewsResponse = await supabase
          .from('product_reviews')
          .select('rating, created_at')
          .inFilter('product_id', productIds);

      final reviews = reviewsResponse as List;
      if (reviews.isNotEmpty) {
        final totalRating = reviews.fold<num>(0, (sum, r) => sum + (r['rating'] as num));
        averageRating = (totalRating / reviews.length).toDouble();
        newReviews = reviews.where((r) {
          final createdAt = r['created_at'] as String?;
          if (createdAt == null) return false;
          return DateTime.parse(createdAt).millisecondsSinceEpoch >= sevenDaysAgo;
        }).length;
      }
    }

    final thirtyDaysAgoMs = DateTime.now().toUtc().subtract(const Duration(days: 30)).millisecondsSinceEpoch;

    final recentProducts = allProducts.where((p) {
      final createdAt = p['created_at'] as String?;
      if (createdAt == null) return false;
      return DateTime.parse(createdAt).millisecondsSinceEpoch >= thirtyDaysAgoMs;
    }).length;

    final followersList = await supabase
        .from('seller_follows')
        .select('id')
        .eq('seller_id', userId);
    final followersCount = (followersList as List).length;

    int pendingOrders = 0;
    int totalSold = 0;
    double totalRevenue = 0;

    if (productIds.isNotEmpty) {
      final orderItemsResponse = await supabase
          .from('order_items')
          .select('order_id, price, quantity, product_id')
          .inFilter('product_id', productIds);

      final orderItems = orderItemsResponse as List;

      // Sum up quantities sold from order_items
      totalSold = orderItems.fold<int>(0, (sum, oi) => sum + ((oi['quantity'] as num?)?.toInt() ?? 0));

      if (orderItems.isNotEmpty) {
        final orderIds = orderItems.map((oi) => oi['order_id'] as String).toSet().toList();

        final ordersResponse = await supabase
            .from('orders')
            .select('id, payment_status, status')
            .inFilter('id', orderIds);

        final orders = ordersResponse as List;
        final orderMap = {for (final o in orders) o['id'] as String: o};

        for (final oi in orderItems) {
          final order = orderMap[oi['order_id'] as String];
          if (order != null) {
            // Pending = not delivered yet (pending, paid, processing, etc.)
            if (order['status'] != 'delivered' && order['status'] != 'cancelled') {
              pendingOrders++;
            }
            if (order['payment_status'] == 'paid') {
              totalRevenue += (oi['price'] as num).toDouble() * (oi['quantity'] as num).toInt();
            }
          }
        }
      }
    }

    return DashboardStats(
      totalProducts: totalProducts,
      averageRating: double.parse(averageRating.toStringAsFixed(1)),
      activeViews: recentProducts,
      followersCount: followersCount,
      pendingOrders: pendingOrders,
      newReviews: newReviews,
      totalSold: totalSold,
      activeListings: activeListings,
      totalRevenue: totalRevenue,
    );
  }

  static Future<List<ProductReview>> getProductReviews(
    String userId, {
    int offset = 0,
    int limit = 20,
  }) async {
    final supabase = SupabaseService.instance;

    final productIdsResponse = await supabase
        .from('products')
        .select('id')
        .eq('seller_id', userId);

    final productIds = (productIdsResponse as List).map((p) => p['id'] as String).toList();
    if (productIds.isEmpty) return [];

    final response = await supabase
        .from('product_reviews')
        .select('''
          *,
          reviewer:users!reviewer_id(full_name, avatar_url),
          product:products!product_id(title, image_urls),
          replies:product_review_replies(*)
        ''')
        .inFilter('product_id', productIds)
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return Isolate.run(() => _parseReviewList(response as List));
  }

  static Future<void> replyToReview({
    required String reviewId,
    required String sellerId,
    required String reply,
  }) async {
    await SupabaseService.table('product_review_replies').insert({
      'review_id': reviewId,
      'seller_id': sellerId,
      'reply': reply,
    });
  }

  static Future<void> updateReply({
    required String reviewId,
    required String reply,
  }) async {
    await SupabaseService.table('product_review_replies')
        .update({'reply': reply})
        .eq('review_id', reviewId);
  }

  static Future<Map<String, dynamic>> getAnalytics(String userId) async {
    final supabase = SupabaseService.instance;

    final productIdsResponse = await supabase
        .from('products')
        .select('id')
        .eq('seller_id', userId);
    final productIds = (productIdsResponse as List).map((p) => p['id'] as String).toList();

    int totalOrders = 0;
    double totalEarned = 0;
    double monthRevenue = 0;
    int avgOrderValue = 0;

    if (productIds.isNotEmpty) {
      final orderItemsResponse = await supabase
          .from('order_items')
          .select('order_id, price, quantity, created_at')
          .inFilter('product_id', productIds);

      final items = orderItemsResponse as List;
      if (items.isNotEmpty) {
        final orderIds = items.map((oi) => oi['order_id'] as String).toSet().toList();

        final ordersResponse = await supabase
            .from('orders')
            .select('id, payment_status, created_at')
            .inFilter('id', orderIds);

        final orders = ordersResponse as List;
        final orderMap = {for (final o in orders) o['id'] as String: o};
        totalOrders = items.length;

      final monthStartMs = DateTime.now().toUtc().subtract(const Duration(days: 30)).millisecondsSinceEpoch;

      for (final item in items) {
        final order = orderMap[item['order_id'] as String];
        if (order != null && order['payment_status'] == 'paid') {
          final itemTotal = (item['price'] as num).toDouble() * (item['quantity'] as num).toInt();
          totalEarned += itemTotal;

          final itemDate = item['created_at'] as String?;
          if (itemDate != null && DateTime.parse(itemDate).millisecondsSinceEpoch >= monthStartMs) {
            monthRevenue += itemTotal;
          }
        }
      }

        if (totalOrders > 0) {
          avgOrderValue = (totalEarned / totalOrders).round();
        }
      }
    }

    return {
      'totalOrders': totalOrders,
      'totalEarned': totalEarned,
      'monthRevenue': monthRevenue,
      'avgOrderValue': avgOrderValue,
    };
  }

  static Future<Map<String, dynamic>> verifyDelivery(String orderItemId, String code) async {
    final result = await SupabaseService.client.rpc(
      'verify_delivery',
      params: {
        'p_order_item_id': orderItemId,
        'p_code': code,
      },
    );
    return result as Map<String, dynamic>;
  }

  static Future<void> completeOrderItem(String orderItemId) async {
    final response = await SupabaseService.client.rpc(
      'complete_seller_order_item',
      params: {'p_order_item_id': orderItemId},
    );
    final result = _asMap(response);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to complete order item');
    }
  }

  static Future<void> cancelOrderItem(String orderItemId, {String? reason}) async {
    final response = await SupabaseService.client.rpc(
      'cancel_seller_order_item',
      params: {
        'p_order_item_id': orderItemId,
        'p_reason': reason,
      },
    );
    final result = _asMap(response);
    if (result['success'] != true) {
      throw Exception(result['error'] ?? 'Failed to cancel order item');
    }
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return Map<String, dynamic>.from(value as Map);
  }

  static Future<List<Order>> getSellerOrders(String userId) async {
    final productIdsResponse = await SupabaseService.table('products')
        .select('id')
        .eq('seller_id', userId);
    final productIds = (productIdsResponse as List).map((p) => _asMap(p)['id'] as String).toList();
    if (productIds.isEmpty) return [];

    final orderItemsResponse = await SupabaseService.table('order_items')
        .select('order_id, product_id, product_title, product_thumbnail, quantity, price, delivery_code, status, id')
        .inFilter('product_id', productIds);

    final orderItems = (orderItemsResponse as List).map(_asMap).toList();
    if (orderItems.isEmpty) return [];

    final orderIds = orderItems.map((oi) => oi['order_id'] as String).toSet().toList();

    final ordersResponse = await SupabaseService.table('orders')
        .select('*')
        .inFilter('id', orderIds)
        .order('created_at', ascending: false);

    final orders = (ordersResponse as List).map(_asMap).toList();
    return orders.map((o) {
      final items = orderItems
          .where((oi) => oi['order_id'] == o['id'])
          .map((oi) => OrderItem.fromJson({
                ...oi,
                'order_id': oi['order_id'],
              }))
          .toList();

      return Order(
        id: o['id'] as String,
        buyerId: o['buyer_id'] as String,
        totalAmount: (o['total_amount'] as num).toDouble(),
        deliveryFee: o['delivery_fee'] != null ? (o['delivery_fee'] as num).toDouble() : 0.0,
        itemQuantityTotal: (o['item_quantity_total'] as num?)?.toInt() ?? items.length,
        status: o['status'] as String? ?? 'pending',
        paymentStatus: o['payment_status'] as String? ?? 'unpaid',
        deliveryMode: o['delivery_mode'] as String?,
        deliveryInstitution: o['delivery_institution'] as String?,
        createdAt: DateTime.parse(o['created_at'] as String),
        items: items,
        sellerId: userId,
      );
    }).toList();
  }
}
