import 'package:flutter/material.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';
import '../services/supabase_service.dart';

class CartProvider extends ChangeNotifier {
  CartState _cart = CartState();
  bool _isLoading = false;
  String? _error;

  CartState get cart => _cart;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get itemCount => _cart.itemCount;

  bool isInCart(String productId) {
    return _cart.items.any((item) => item.productId == productId);
  }

  Future<void> loadCart() async {
    _isLoading = true;
    notifyListeners();

    try {
      _cart = await CartService.getCartState();
      await _removeOwnProducts();
      await _validateStock();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Remove products where the current user is the seller.
  Future<void> _removeOwnProducts() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null || _cart.items.isEmpty) return;

    final ownItems = _cart.items.where((i) => i.sellerId == userId).toList();
    if (ownItems.isEmpty) return;

    for (final item in ownItems) {
      await CartService.removeFromCart(item.productId);
    }
    _cart = await CartService.getCartState();
  }

  /// Check current stock from DB, remove out-of-stock items, clamp quantities.
  Future<void> _validateStock() async {
    if (_cart.items.isEmpty) return;

    final productIds = _cart.items.map((i) => i.productId).toList();
    try {
      final response = await SupabaseService.client
          .from('products')
          .select('id, stock_quantity')
          .inFilter('id', productIds);

      final stockMap = <String, int>{
        for (final row in response)
          row['id'] as String: (row['stock_quantity'] as num?)?.toInt() ?? 0,
      };

      bool changed = false;

      for (final item in _cart.items) {
        final currentStock = stockMap[item.productId];
        if (currentStock == null || currentStock <= 0) {
          // Product no longer available — remove from cart
          await CartService.removeFromCart(item.productId);
          changed = true;
          continue;
        }
        if (item.quantity > currentStock || item.stock != currentStock) {
          final newQty = item.quantity > currentStock ? currentStock : item.quantity;
          // Clamp quantity and update stock quantity to match DB
          await CartService.updateCartItemQuantity(item.productId, newQty, stock: currentStock);
          changed = true;
        }
      }

      if (changed) {
        _cart = await CartService.getCartState();
      }
    } catch (_) {
      // On network error, keep cart as-is — don't lose user's items
    }
  }

  Future<void> addToCart({
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
    try {
      await CartService.addToCart(
        productId: productId,
        title: title,
        price: price,
        thumbnail: thumbnail,
        sellerId: sellerId,
        sellerName: sellerName,
        quantity: quantity,
        deliveryFee: deliveryFee,
        stock: stock,
      );
      await loadCart();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateQuantity(String productId, int quantity) async {
    try {
      if (quantity <= 0) {
        await removeItem(productId);
        return;
      }
      // Optimistic update — mutate local state immediately
      final index = _cart.items.indexWhere((i) => i.productId == productId);
      if (index == -1) return;
      final oldItem = _cart.items[index];
      final updatedItem = oldItem.copyWith(quantity: quantity);
      final newItems = List<CartItem>.from(_cart.items);
      newItems[index] = updatedItem;
      _cart = _cart.copyWith(items: newItems);
      notifyListeners();
      // Persist in background
      CartService.updateCartItemQuantity(productId, quantity); // ignore: unawaited_futures
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> removeItem(String productId) async {
    try {
      // Optimistic remove
      final newItems = _cart.items.where((i) => i.productId != productId).toList();
      _cart = _cart.copyWith(items: newItems);
      notifyListeners();
      CartService.removeFromCart(productId); // ignore: unawaited_futures
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> clearCart() async {
    try {
      await CartService.clearCart();
      _cart = CartState();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
