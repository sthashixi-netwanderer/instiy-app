import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/institution_model.dart';
import '../services/product_service.dart';
import '../services/institution_service.dart';
import '../services/supabase_service.dart';
import '../providers/block_provider.dart';

class HomeProvider extends ChangeNotifier {
  List<Product> _featuredProducts = [];
  List<Product> _trendingProducts = [];
  List<Product> _bestSellers = [];
  List<Institution> _institutions = [];
  String? _businessName;
  bool _isLoading = false;
  String? _error;
  bool _initialized = false;
  double _scrollOffset = 0;

  RealtimeChannel? _productsChannel;
  String? _currentUserId;

  HomeProvider() {
    _initAuthListener();
    BlockProvider.instance.addListener(_onBlocksChanged);
  }

  void _onBlocksChanged() {
    // Re-fetch from server because unblocked products need to reappear
    // (re-filtering an already-filtered list can't bring removed items back)
    _silentReload();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        final userId = session.user.id;
        if (_currentUserId == userId) return;
        _currentUserId = userId;
        _subscribeToRealtime();
        // Reload business name for new user
        _loadBusinessName();
      } else {
        _unsubscribeFromRealtime();
        _currentUserId = null;
        _businessName = null;
        _initialized = false;
        loadAll();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      _subscribeToRealtime();
    }
  }

  /// Initialize data once. Subsequent calls are no-ops unless [force] is true.
  Future<void> ensureInitialized({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;

    // Batch all loads, then notify once at the end
    _isLoading = true;
    _error = null;
    try {
      await Future.wait([
        _loadAllSilent(),
        _loadInstitutions(),
        _loadBusinessName(),
      ]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Silent version that doesn't call notifyListeners (for batched init)
  Future<void> _loadAllSilent() async {
    try {
      final results = await Future.wait([
        ProductService.getFeaturedProducts(),
        ProductService.getTrendingProducts(),
        ProductService.getBestSellers(),
      ]);
      final blockProv = BlockProvider.instance;
      _featuredProducts = blockProv.filterProducts(results[0]);
      _trendingProducts = blockProv.filterProducts(results[1]);
      _bestSellers = blockProv.filterProducts(results[2]);
    } catch (_) {}
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
      final blockProv = BlockProvider.instance;
      _featuredProducts = blockProv.filterProducts(results[0]);
      _trendingProducts = blockProv.filterProducts(results[1]);
      _bestSellers = blockProv.filterProducts(results[2]);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadInstitutions() async {
    try {
      _institutions = await InstitutionService.getInstitutions();
    } catch (_) {}
  }

  Future<void> _loadBusinessName() async {
    try {
      final uid = SupabaseService.instance.currentUser?.id;
      if (uid == null) return;
      final data = await SupabaseService.table('business_profiles')
          .select('business_name')
          .eq('seller_id', uid)
          .maybeSingle();
      if (data != null) {
        _businessName = data['business_name'] as String?;
      }
    } catch (_) {}
  }

  void clearSession() {
    _featuredProducts = [];
    _trendingProducts = [];
    _bestSellers = [];
    _institutions = [];
    _businessName = null;
    _error = null;
    _initialized = false;
    _scrollOffset = 0;
    notifyListeners();
  }

  List<Product> get featuredProducts => _featuredProducts;
  List<Product> get trendingProducts => _trendingProducts;
  List<Product> get bestSellers => _bestSellers;
  List<Institution> get institutions => _institutions;
  String? get businessName => _businessName;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialized => _initialized;
  double get scrollOffset => _scrollOffset;

  void saveScrollOffset(double offset) {
    _scrollOffset = offset;
  }

  Institution? findInstitution(String? universityName) {
    if (universityName == null || universityName.isEmpty || _institutions.isEmpty) return null;
    try {
      return _institutions.firstWhere(
        (i) => i.name.toLowerCase() == universityName.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

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
      final blockProv = BlockProvider.instance;
      _featuredProducts = blockProv.filterProducts(results[0]);
      _trendingProducts = blockProv.filterProducts(results[1]);
      _bestSellers = blockProv.filterProducts(results[2]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Called when user pulls to refresh — reload everything fresh
  Future<void> refresh() async {
    await Future.wait([
      _loadAllSilent(),
      _loadInstitutions(),
      _loadBusinessName(),
    ]);
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    BlockProvider.instance.removeListener(_onBlocksChanged);
    super.dispose();
  }
}
