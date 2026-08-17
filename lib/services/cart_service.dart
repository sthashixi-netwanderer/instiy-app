import 'dart:convert';
import 'dart:isolate';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_model.dart';

// Top-level function for isolate — parses raw JSON string into CartItems
List<CartItem> _parseCartItems(String data) {
  final list = jsonDecode(data) as List<dynamic>;
  return list.map((e) => CartItem.fromJson(e as Map<String, dynamic>)).toList();
}

// Top-level function for isolate — encodes CartItems to JSON string
String _encodeCartItems(List<CartItem> items) {
  return jsonEncode(items.map((e) => e.toJson()).toList());
}

class CartService {
  static const _cartKey = 'cart_items';

  static Future<CartState> getCartState() async {
    final items = await _loadItems();
    final subtotal = items.fold<double>(0, (sum, item) => sum + item.totalPrice);
    return CartState(
      items: items,
      itemCount: items.fold(0, (sum, item) => sum + item.quantity),
      subtotalAmount: subtotal,
      totalAmount: subtotal,
    );
  }

  static Future<int> getCartCount() async {
    final items = await _loadItems();
    return items.fold<int>(0, (sum, item) => sum + item.quantity);
  }

  static Future<void> addToCart({
    required String productId,
    required String title,
    required double price,
    String? thumbnail,
    String? sellerId,
    String? sellerName,
    int quantity = 1,
    double deliveryFee = 0.0,
    int? stock,
  }) async {
    final items = await _loadItems();
    final idx = items.indexWhere((i) => i.productId == productId);

    if (idx >= 0) {
      final existing = items[idx];
      final newQty = existing.quantity + quantity;
      final cappedQty = stock != null ? newQty.clamp(1, stock) : newQty;
      items[idx] = CartItem(
        id: existing.id,
        productId: existing.productId,
        title: existing.title,
        thumbnail: existing.thumbnail,
        price: existing.price,
        quantity: cappedQty,
        stock: stock ?? existing.stock,
        sellerId: existing.sellerId,
        sellerName: existing.sellerName,
        deliveryFee: deliveryFee,
      );
    } else {
      items.add(CartItem(
        id: productId,
        productId: productId,
        title: title,
        thumbnail: thumbnail,
        price: price,
        quantity: quantity,
        stock: stock,
        sellerId: sellerId,
        sellerName: sellerName,
        deliveryFee: deliveryFee,
      ));
    }

    await _saveItems(items);
  }

  static Future<void> updateCartItemQuantity(String productId, int quantity, {int? stock}) async {
    final items = await _loadItems();
    final idx = items.indexWhere((i) => i.productId == productId);
    if (idx < 0) return;

    if (quantity <= 0) {
      items.removeAt(idx);
    } else {
      final currentStock = stock ?? items[idx].stock;
      final capped = currentStock != null ? quantity.clamp(1, currentStock) : quantity;
      items[idx] = CartItem(
        id: items[idx].id,
        productId: items[idx].productId,
        title: items[idx].title,
        thumbnail: items[idx].thumbnail,
        price: items[idx].price,
        quantity: capped,
        stock: currentStock,
        sellerId: items[idx].sellerId,
        sellerName: items[idx].sellerName,
        isAvailable: items[idx].isAvailable,
        deliveryFee: items[idx].deliveryFee,
      );
    }

    await _saveItems(items);
  }

  static Future<void> removeFromCart(String productId) async {
    final items = await _loadItems();
    items.removeWhere((i) => i.productId == productId);
    await _saveItems(items);
  }

  static Future<void> clearCart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cartKey);
  }

  static Future<List<CartItem>> _loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(_cartKey);
    if (data == null) return [];
    return Isolate.run(() => _parseCartItems(data));
  }

  static Future<void> _saveItems(List<CartItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final data = await Isolate.run(() => _encodeCartItems(items));
    await prefs.setString(_cartKey, data);
  }
}
