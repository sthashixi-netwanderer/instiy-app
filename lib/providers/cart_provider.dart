import 'package:flutter/material.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';

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
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
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
      );
      await loadCart();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> updateQuantity(String productId, int quantity) async {
    try {
      await CartService.updateCartItemQuantity(productId, quantity);
      await loadCart();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> removeItem(String productId) async {
    try {
      await CartService.removeFromCart(productId);
      await loadCart();
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
