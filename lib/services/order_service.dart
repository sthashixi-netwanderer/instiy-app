import 'dart:isolate';
import 'supabase_service.dart';
import '../models/order_model.dart';
import '../models/cart_model.dart';

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  return Map<String, dynamic>.from(value as Map);
}

class OrderService {
  static Future<List<Order>> getOrders() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return [];

    final response = await supabase
        .from('orders')
        .select('''
          *,
          items:order_items(*)
        ''')
        .eq('buyer_id', uid)
        .order('created_at', ascending: false);

    return Isolate.run(() => _parseOrderList(response));
  }

  static List<Order> _parseOrderList(List<Map<String, dynamic>> response) {
    return response.map((json) => Order.fromJson(_asMap(json))).toList();
  }

  static Future<Order?> getOrder(String orderId) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return null;

    final response = await supabase
        .from('orders')
        .select('*, items:order_items(*)')
        .eq('id', orderId)
        .maybeSingle();

    if (response == null) return null;
    return Order.fromJson(_asMap(response));
  }

  static Future<Map<String, dynamic>?> createOrder({
    required String deliveryMode,
    required String paymentMethod,
    required List<CartItem> cartItems,
    String? paymentReference,
    String? deliveryInstitution,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return null;

    // Ensure all items have a valid seller_id (old cart data may lack it)
    final missingIds = cartItems.where((i) => (i.sellerId ?? '').isEmpty).map((i) => i.productId).toList();
    Map<String, String> sellerLookup = {};
    if (missingIds.isNotEmpty) {
      final rows = await SupabaseService.client
          .from('products')
          .select('id, seller_id')
          .inFilter('id', missingIds);
      for (final row in rows) {
        sellerLookup[row['id'] as String] = row['seller_id'] as String;
      }
    }

    final itemsJson = cartItems.map((item) => {
      'product_id': item.productId,
      'product_title': item.title,
      'product_thumbnail': item.thumbnail,
      'quantity': item.quantity,
      'price': item.price,
      'seller_id': sellerLookup[item.productId] ?? item.sellerId,
    }).toList();

    final response = await SupabaseService.client.rpc(
      'place_order_with_items',
      params: {
        'p_buyer_id': uid,
        'p_items': itemsJson,
        'p_delivery_mode': deliveryMode,
        'p_payment_method': paymentMethod,
        'p_payment_reference': paymentReference,
        'p_delivery_institution': deliveryInstitution,
      },
    );

    if (response == null) return null;
    return _asMap(response);
  }

  static Future<bool> cancelOrder(String orderId) async {
    final result = await SupabaseService.client.rpc('cancel_order', params: {'order_id': orderId});
    return result == true;
  }
}
