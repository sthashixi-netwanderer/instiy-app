import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../models/draft_listing_model.dart';
import '../services/draft_service.dart';
import '../providers/block_provider.dart';
import '../services/follow_service.dart';
import '../services/product_service.dart';
import '../services/supabase_service.dart';

class ProductProvider extends ChangeNotifier {
  List<Product> _products = [];
  List<Product> _userListings = [];
  List<Category> _categories = [];
  List<String> _favoriteIds = [];
  bool _isLoading = false;
  String? _error;
  String? _selectedCategoryId;
  String? _searchQuery;

  // Publishing draft state (reactive for dashboard)
  DraftListing? _publishingDraft;
  double _publishProgress = 0;
  DraftListing? get publishingDraft => _publishingDraft;
  double get publishProgress => _publishProgress;

  RealtimeChannel? _productsChannel;
  RealtimeChannel? _categoriesChannel;

  String? _currentUserId;
  int _productsVersion = 0;

  ProductProvider() {
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
        clearSession();
        _currentUserId = null;
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
        .channel('public-products')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'products',
          callback: (payload) => _handleProductChange(payload),
        );
    _productsChannel!.subscribe();

    _categoriesChannel = SupabaseService.client
        .channel('public-categories')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'categories',
          callback: (_) => _silentReloadCategories(),
        );
    _categoriesChannel!.subscribe();
  }

  void _unsubscribeFromRealtime() {
    for (final ch in [_productsChannel, _categoriesChannel]) {
      if (ch != null) SupabaseService.client.removeChannel(ch);
    }
    _productsChannel = null;
    _categoriesChannel = null;
  }

  Future<void> _handleProductChange(PostgresChangePayload payload) async {
    try {
      final eventType = payload.eventType;
      final oldRecord = payload.oldRecord;

      if (eventType == PostgresChangeEvent.delete) {
        final deletedId = oldRecord['id'] as String?;
        if (deletedId == null) return;
        _products.removeWhere((p) => p.id == deletedId);
        _userListings.removeWhere((p) => p.id == deletedId);
        _productsVersion++;
        notifyListeners();
        return;
      }

      final newRecord = payload.newRecord;
      final productId = newRecord['id'] as String?;
      if (productId == null) return;

      final product = await ProductService.getProduct(productId);
      final currentUser = SupabaseService.auth.currentUser;

      final belongs = product.status == ProductStatus.available &&
          product.stockQuantity > 0 &&
          !BlockProvider.instance.isUserBlocked(product.sellerId) &&
          (_selectedCategoryId == null || product.categoryId == _selectedCategoryId) &&
          (_searchQuery == null || _searchQuery!.isEmpty ||
              product.title.toLowerCase().contains(_searchQuery!.toLowerCase()) ||
              product.description.toLowerCase().contains(_searchQuery!.toLowerCase()));

      if (eventType == PostgresChangeEvent.insert) {
        if (belongs && !_products.any((p) => p.id == productId)) {
          _products.insert(0, product);
        }
        if (currentUser != null && product.sellerId == currentUser.id) {
          _userListings.insert(0, product);
        }
      } else if (eventType == PostgresChangeEvent.update) {
        final inProducts = _products.any((p) => p.id == productId);
        if (inProducts) {
          if (belongs) {
            final idx = _products.indexWhere((p) => p.id == productId);
            _products[idx] = product;
          } else {
            _products.removeWhere((p) => p.id == productId);
          }
        } else if (belongs) {
          _products.insert(0, product);
        }

        final inListings = _userListings.any((p) => p.id == productId);
        if (currentUser != null && product.sellerId == currentUser.id) {
          if (inListings) {
            final idx = _userListings.indexWhere((p) => p.id == productId);
            _userListings[idx] = product;
          } else {
            _userListings.insert(0, product);
          }
        } else if (inListings) {
          _userListings.removeWhere((p) => p.id == productId);
        }
      }

      _productsVersion++;
      notifyListeners();
    } catch (_) {
      _silentReloadProducts(); // ignore: unawaited_futures
    }
  }

  Future<void> _silentReloadProducts() async {
    try {
      _products = await ProductService.getProducts(
        categoryId: _selectedCategoryId,
        searchQuery: _searchQuery,
      );
      final currentUser = SupabaseService.auth.currentUser;
      if (currentUser != null) {
        _userListings = await ProductService.getUserListings(currentUser.id);
      }
      _productsVersion++;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _silentReloadCategories() async {
    try {
      _categories = await ProductService.getCategories();
      notifyListeners();
    } catch (_) {}
  }

  void clearSession() {
    _products = [];
    _userListings = [];
    _categories = [];
    _favoriteIds = [];
    _selectedCategoryId = null;
    _searchQuery = null;
    _error = null;
    notifyListeners();
  }

  List<Product> get products => _products;
  List<Product> get userListings => _userListings;
  List<Category> get categories => _categories;
  List<String> get favoriteIds => _favoriteIds;
  /// Bumped whenever a realtime product change (insert/update/delete) is
  /// applied, so screens can react to product data changes precisely.
  int get productsVersion => _productsVersion;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get selectedCategoryId => _selectedCategoryId;
  String? get searchQuery => _searchQuery;

  /// Load publishing draft from SharedPreferences into reactive state
  Future<void> loadPublishingDraft() async {
    final draft = await DraftService.loadDraft();
    _publishingDraft = draft;
    _publishProgress = draft?.status == DraftStatus.publishing ? 0 : 0;
    notifyListeners();
  }

  /// Update publishing draft state (called from background publish)
  void updatePublishingDraft(DraftListing? draft, {double? progress}) {
    _publishingDraft = draft;
    if (progress != null) _publishProgress = progress;
    notifyListeners();
  }

  Future<void> loadProducts({bool refresh = false}) async {
    if (_isLoading) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _products = await ProductService.getProducts(
        categoryId: _selectedCategoryId,
        searchQuery: _searchQuery,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadCategories() async {
    try {
      _categories = await ProductService.getCategories();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    }
  }

  Future<Product?> getProduct(String productId) async {
    try {
      return await ProductService.getProduct(productId);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<bool> createProduct({
    required String title,
    required String description,
    required double price,
    String? categoryId,
    required List<String> imageUrls,
    List<String> videoUrls = const [],
    required ProductCondition condition,
    List<String>? campuses,
    List<Map<String, String>>? specifications,
    int stockQuantity = 1,
    String deliveryOption = 'pickup',
    double deliveryFee = 0.0,
    double discountPercent = 0,
    String? discountStartDate,
    String? discountEndDate,
    String? thumbnailUrl,
    Map<String, double>? institutionDeliveryFees,
    bool showOnClips = false,
    String? clipVideoUrl,
  }) async {
    try {
      final product = await ProductService.createProduct(
        title: title,
        description: description,
        price: price,
        categoryId: categoryId,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        condition: condition,
        campuses: campuses,
        specifications: specifications,
        stockQuantity: stockQuantity,
        deliveryOption: deliveryOption,
        deliveryFee: deliveryFee,
        institutionDeliveryFees: institutionDeliveryFees,
        discountPercent: discountPercent,
        discountStartDate: discountStartDate,
        discountEndDate: discountEndDate,
        thumbnailUrl: thumbnailUrl,
        showOnClips: showOnClips,
        clipVideoUrl: clipVideoUrl,
      );

      _products.insert(0, product);
      _userListings.insert(0, product);
      notifyListeners();

      // Notify followers about the new product (fire-and-forget)
      final currentUser = SupabaseService.auth.currentUser;
      if (currentUser != null) {
        final sellerName = product.sellerName ?? 'A seller';
        final thumb = product.thumbnailUrl ??
            (product.imageUrls.isNotEmpty ? product.imageUrls.first : null);
        FollowService.notifyFollowersOfNewProduct( // ignore: unawaited_futures
          sellerId: currentUser.id,
          sellerName: sellerName,
          productId: product.id,
          productTitle: product.title,
          productPrice: product.price,
          productThumbnail: thumb,
        );
      }

      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProduct({
    required String productId,
    String? title,
    String? description,
    double? price,
    String? categoryId,
    List<String>? imageUrls,
    List<String>? videoUrls,
    ProductCondition? condition,
    ProductStatus? status,
    List<String>? campuses,
    List<Map<String, String>>? specifications,
    int? stockQuantity,
    String? deliveryOption,
    double? deliveryFee,
    double? discountPercent,
    String? discountStartDate,
    String? discountEndDate,
    String? thumbnailUrl,
    Map<String, double>? institutionDeliveryFees,
    bool? showOnClips,
    String? clipVideoUrl,
  }) async {
    try {
      final updatedProduct = await ProductService.updateProduct(
        productId: productId,
        title: title,
        description: description,
        price: price,
        categoryId: categoryId,
        imageUrls: imageUrls,
        videoUrls: videoUrls,
        condition: condition,
        status: status,
        campuses: campuses,
        specifications: specifications,
        stockQuantity: stockQuantity,
        deliveryOption: deliveryOption,
        deliveryFee: deliveryFee,
        institutionDeliveryFees: institutionDeliveryFees,
        discountPercent: discountPercent,
        discountStartDate: discountStartDate,
        discountEndDate: discountEndDate,
        thumbnailUrl: thumbnailUrl,
        showOnClips: showOnClips,
        clipVideoUrl: clipVideoUrl,
      );

      final index = _products.indexWhere((p) => p.id == productId);
      if (index != -1) {
        _products[index] = updatedProduct;
      }
      final userIdx = _userListings.indexWhere((p) => p.id == productId);
      if (userIdx != -1) {
        _userListings[userIdx] = updatedProduct;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<String?> deleteProduct(String productId) async {
    try {
      final error = await ProductService.deleteProduct(productId);
      if (error != null) return error;
      _products.removeWhere((p) => p.id == productId);
      _userListings.removeWhere((p) => p.id == productId);
      notifyListeners();
      return null;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return e.toString();
    }
  }

  void setCategory(String? categoryId) {
    _selectedCategoryId = categoryId;
    notifyListeners();
    loadProducts(refresh: true);
  }

  void setSearchQuery(String? query) {
    _searchQuery = query;
    notifyListeners();
    loadProducts(refresh: true);
  }

  void clearFilters() {
    _selectedCategoryId = null;
    _searchQuery = null;
    notifyListeners();
    loadProducts(refresh: true);
  }

  Future<void> loadUserListings(String userId, {bool silent = false}) async {
    final showLoading = !silent && _userListings.isEmpty;
    if (showLoading) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      _userListings = await ProductService.getUserListings(userId);
    } catch (e) {
      _error = e.toString();
    } finally {
      if (showLoading) {
        _isLoading = false;
      }
      notifyListeners();
    }
  }

  Future<void> loadFavoriteIds() async {
    try {
      _favoriteIds = await ProductService.getFavoriteIds();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    }
  }

  bool isFavorited(String productId) {
    return _favoriteIds.contains(productId);
  }

  Future<void> toggleFavorite(String productId) async {
    try {
      if (_favoriteIds.contains(productId)) {
        await ProductService.removeFavorite(productId);
        _favoriteIds.remove(productId);
      } else {
        await ProductService.addFavorite(productId);
        _favoriteIds.add(productId);
      }
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
