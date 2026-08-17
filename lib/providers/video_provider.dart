import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../services/product_service.dart';
import '../services/supabase_service.dart';
import '../providers/block_provider.dart';

class VideoProvider extends ChangeNotifier {
  List<Product> _products = [];
  bool _isLoading = false;
  String? _error;
  int _focusedIndex = 0;
  bool _initialized = false;

  RealtimeChannel? _productsChannel;

  VideoProvider() {
    _initAuthListener();
    BlockProvider.instance.addListener(_onBlocksChanged);
  }

  void _onBlocksChanged() {
    // Re-fetch from server because unblocked products need to reappear
    refresh();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session == null) {
        _unsubscribeFromRealtime();
        clearSession();
      } else {
        _subscribeToRealtime();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _subscribeToRealtime();
    }
  }

  Future<void> ensureInitialized({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;
    await loadVideos(silent: _products.isNotEmpty);
  }

  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    _productsChannel = SupabaseService.client
        .channel('products-changes-video')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            final newProduct = payload.newRecord;
            if (newProduct['status'] != 'available') return;
            if (newProduct['stock_quantity'] == null || newProduct['stock_quantity'] <= 0) return;
            if (newProduct['video_urls'] == null ||
                (newProduct['video_urls'] as List).isEmpty) {
              return;
            }
            loadVideos(silent: true);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'products',
          callback: (payload) {
            final deletedId = payload.oldRecord['id'] as String?;
            if (deletedId == null) return;
            _products.removeWhere((p) => p.id == deletedId);
            notifyListeners();
          },
        )
        .subscribe();
  }

  void _unsubscribeFromRealtime() {
    if (_productsChannel != null) {
      SupabaseService.client.removeChannel(_productsChannel!);
      _productsChannel = null;
    }
  }

  void clearSession() {
    _products = [];
    _focusedIndex = 0;
    _isLoading = false;
    _error = null;
    _initialized = false;
    notifyListeners();
  }

  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get focusedIndex => _focusedIndex;
  bool get isInitialized => _initialized;

  void setFocusedIndex(int index) {
    if (_focusedIndex == index) return;
    _focusedIndex = index;
    notifyListeners();
  }

  Future<void> loadVideos({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

    try {
      final clips = await ProductService.getClipsProducts();
      _products = BlockProvider.instance.filterProducts(clips);
      if (_focusedIndex >= _products.length) {
        _focusedIndex = 0;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (!silent) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await loadVideos(silent: true);
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    BlockProvider.instance.removeListener(_onBlocksChanged);
    super.dispose();
  }
}
