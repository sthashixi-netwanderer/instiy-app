import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/supabase_service.dart';

class HomeProvider extends ChangeNotifier {
  List<Product> _featuredProducts = [];
  List<Product> _trendingProducts = [];
  List<Product> _bestSellers = [];
  bool _isLoading = false;
  String? _error;

  RealtimeChannel? _productsChannel;
  String? _currentUserId;

  HomeProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        final userId = session.user.id;
        if (_currentUserId == userId) return;
        _currentUserId = userId;
        _subscribeToRealtime();
      } else {
        _unsubscribeFromRealtime();
        _currentUserId = null;
        loadAll();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      _subscribeToRealtime();
    }
  }

  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    _productsChannel = SupabaseService.client
        .channel('public-products-home')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (_) => _silentReload(),
        );
    _productsChannel!.subscribe();
  }

  void _unsubscribeFromRealtime() {
    if (_productsChannel != null) {
      SupabaseService.client.removeChannel(_productsChannel!);
      _productsChannel = null;
    }
  }

  Future<void> _silentReload() async {
    try {
      final results = await Future.wait([
        ProductService.getFeaturedProducts(),
        ProductService.getTrendingProducts(),
        ProductService.getBestSellers(),
      ]);
      _featuredProducts = results[0];
      _trendingProducts = results[1];
      _bestSellers = results[2];
      notifyListeners();
    } catch (_) {}
  }

  void clearSession() {
    _featuredProducts = [];
    _trendingProducts = [];
    _bestSellers = [];
    _error = null;
    notifyListeners();
  }

  List<Product> get featuredProducts => _featuredProducts;
  List<Product> get trendingProducts => _trendingProducts;
  List<Product> get bestSellers => _bestSellers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        ProductService.getFeaturedProducts(),
        ProductService.getTrendingProducts(),
        ProductService.getBestSellers(),
      ]);
      _featuredProducts = results[0];
      _trendingProducts = results[1];
      _bestSellers = results[2];
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
