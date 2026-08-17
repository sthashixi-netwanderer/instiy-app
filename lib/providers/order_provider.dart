import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order_model.dart';
import '../models/cart_model.dart';
import '../services/order_service.dart';
import '../services/supabase_service.dart';
import '../services/local_notification_service.dart';
import '../services/product_service.dart';
import '../services/email_service.dart';

class OrderProvider extends ChangeNotifier {
  List<Order> _orders = [];
  bool _isLoading = false;
  String? _error;

  RealtimeChannel? _ordersChannel;
  RealtimeChannel? _orderItemsChannel;

  String? _currentUserId;

  OrderProvider() {
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
        clearSession();
        _currentUserId = null;
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

    _ordersChannel = SupabaseService.client
        .channel('buyer-orders:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'buyer_id',
            value: userId,
          ),
          callback: (_) => _silentReload(),
        );
    _ordersChannel!.subscribe();

    _orderItemsChannel = SupabaseService.client
        .channel('buyer-order-items:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'order_items',
          callback: (_) => _silentReload(),
        );
    _orderItemsChannel!.subscribe();
  }

  void _unsubscribeFromRealtime() {
    for (final ch in [_ordersChannel, _orderItemsChannel]) {
      if (ch != null) SupabaseService.client.removeChannel(ch);
    }
    _ordersChannel = null;
    _orderItemsChannel = null;
  }

  Future<void> _silentReload() async {
    try {
      _orders = await OrderService.getOrders();
      notifyListeners();
    } catch (_) {}
  }

  void clearSession() {
    _orders = [];
    _error = null;
    notifyListeners();
  }

  List<Order> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<Order?> loadOrder(String orderId) async {
    try {
      return await OrderService.getOrder(orderId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> loadOrders() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _orders = await OrderService.getOrders();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Map<String, dynamic>? _lastOrderResult;

  Map<String, dynamic>? get lastOrderResult => _lastOrderResult;

  Future<String?> placeOrder({
    required String deliveryMode,
    required String paymentMethod,
    required List<CartItem> cartItems,
    String? paymentReference,
    String? deliveryInstitution,
  }) async {
    try {
      final result = await OrderService.createOrder(
        deliveryMode: deliveryMode,
        paymentMethod: paymentMethod,
        cartItems: cartItems,
        paymentReference: paymentReference,
        deliveryInstitution: deliveryInstitution,
      );

      if (result == null) return 'Failed to create order';

      _lastOrderResult = result;
      await loadOrders();

      // Send device notification
      final orderId = result['order_id'] as String?;
      final totalAmount = cartItems.fold<double>(0, (sum, item) => sum + item.totalPrice);
      final deliveryFee = deliveryMode == 'delivery'
          ? cartItems.fold<double>(0, (sum, item) => sum + item.deliveryFee)
          : 0.0;
      if (orderId != null) {
        await LocalNotificationService.notifyOrderPlaced(
          orderId: orderId,
          amount: totalAmount,
          deliveryFee: deliveryFee,
        );

        // Check if any product went out of stock to notify the seller
        for (final item in cartItems) {
          try {
            final product = await ProductService.getProduct(item.productId);
            if (product.stockQuantity <= 0) {
              // Send in-app notification to the seller
              await SupabaseService.table('notifications').insert({
                'user_id': product.sellerId,
                'title': 'Product Out of Stock',
                'body': 'Your product "${product.title}" is now out of stock.',
                'type': 'out_of_stock',
                'data': {'product_id': product.id},
              });

              // Send email notification to the seller
              if (product.sellerEmail != null && product.sellerEmail!.isNotEmpty) {
                await EmailService.sendProductOutOfStock(
                  sellerEmail: product.sellerEmail!,
                  productTitle: product.title,
                );
              }
            } else if (product.stockQuantity < 5) {
              // Low stock warning
              if (product.sellerEmail != null && product.sellerEmail!.isNotEmpty) {
                await EmailService.sendProductLowStock(
                  sellerEmail: product.sellerEmail!,
                  productTitle: product.title,
                  remainingStock: product.stockQuantity,
                );
              }
            }
          } catch (e) {
            debugPrint('Failed to check stock for out-of-stock notification: $e');
          }
        }
      }

      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<bool> cancelOrder(String orderId) async {
    try {
      final success = await OrderService.cancelOrder(orderId);
      if (success) {
        await loadOrders();
      }
      return success;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
