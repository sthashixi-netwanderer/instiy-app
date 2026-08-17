import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../models/institution_model.dart';
import '../services/product_service.dart';
import '../services/institution_service.dart';
import '../services/supabase_service.dart';
import '../providers/block_provider.dart';

class ExploreState extends ChangeNotifier {
  List<Product> _products = [];
  List<Category> _categories = [];
  List<Institution> _institutions = [];
  String? _selectedInstitutionCode;
  bool _isLoading = true;
  bool _hasMore = true;
  int _page = 0;
  String? _businessName;

  String _searchQuery = '';
  String? _selectedCategoryId;
  List<String> _selectedConditions = [];
  double? _minPrice;
  double? _maxPrice;
  String _sortBy = 'random';

  // Search suggestions
  List<Product> _searchSuggestions = [];
  bool _showSuggestions = false;
  Timer? _searchDebounce;

  // Scroll position
  double _scrollOffset = 0;

  // Getters
  List<Product> get products => _products;
  List<Category> get categories => _categories;
  List<Institution> get institutions => _institutions;
  String? get selectedInstitutionCode => _selectedInstitutionCode;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;
  int get page => _page;
  String? get businessName => _businessName;
  String get searchQuery => _searchQuery;
  String? get selectedCategoryId => _selectedCategoryId;
  List<String> get selectedConditions => _selectedConditions;
  double? get minPrice => _minPrice;
  double? get maxPrice => _maxPrice;
  String get sortBy => _sortBy;
  List<Product> get searchSuggestions => _searchSuggestions;
  bool get showSuggestions => _showSuggestions;
  double get scrollOffset => _scrollOffset;

  bool _initialized = false;

  /// Initialize data once. Subsequent calls are no-ops unless [force] is true.
  Future<void> ensureInitialized({bool force = false}) async {
    if (_initialized && !force) return;
    _initialized = true;

    await Future.wait([
      _loadInstitutions(),
      _loadProducts(reset: true),
      _loadCategories(),
      _loadBusinessName(),
    ]);

    // Set default institution to user's university
    final userUid = SupabaseService.instance.currentUser?.id;
    if (userUid != null && _selectedInstitutionCode == null) {
      try {
        final data = await SupabaseService.table('users')
            .select('university')
            .eq('id', userUid)
            .maybeSingle();
        final uni = data?['university'] as String?;
        if (uni != null && uni.isNotEmpty) {
          final match = _institutions
              .where((i) => i.name.toLowerCase() == uni.toLowerCase())
              .toList();
          if (match.isNotEmpty) {
            _selectedInstitutionCode = match.first.code;
            notifyListeners();
            await _loadProducts(reset: true);
          }
        }
      } catch (_) {}
    }
  }

  void saveScrollOffset(double offset) {
    _scrollOffset = offset;
  }

  void setSelectedInstitution(String? code) {
    _selectedInstitutionCode = code;
    notifyListeners();
    _loadProducts(reset: true);
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
  }

  void setSelectedCategoryId(String? id) {
    _selectedCategoryId = id;
  }

  void setSelectedConditions(List<String> conditions) {
    _selectedConditions = conditions;
  }

  void setMinPrice(double? price) {
    _minPrice = price;
  }

  void setMaxPrice(double? price) {
    _maxPrice = price;
  }

  void setSortBy(String sort) {
    _sortBy = sort;
  }

  void applyFilters() {
    _loadProducts(reset: true);
  }

  void clearFilters() {
    _searchQuery = '';
    _selectedCategoryId = null;
    _selectedConditions = [];
    _minPrice = null;
    _maxPrice = null;
    notifyListeners();
    _loadProducts(reset: true);
  }

  void onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      _showSuggestions = false;
      _searchSuggestions = [];
      notifyListeners();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadSuggestions(query);
    });
  }

  void hideSuggestions() {
    _showSuggestions = false;
    notifyListeners();
  }

  Future<void> _loadSuggestions(String query) async {
    try {
      final results = await ProductService.getProducts(
        searchQuery: query,
        limit: 5,
      );
      _searchSuggestions = BlockProvider.instance.filterProducts(results);
      _showSuggestions = results.isNotEmpty;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ProductService.getCategories();
      _categories = categories;
      notifyListeners();
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
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _loadInstitutions() async {
    try {
      final institutions = await InstitutionService.getInstitutionsWithCounts();
      _institutions = institutions;
      notifyListeners();
    } catch (_) {
      try {
        final institutions = await InstitutionService.getInstitutions();
        _institutions = institutions;
        notifyListeners();
      } catch (_) {}
    }
  }

  Future<void> _loadProducts({bool reset = false}) async {
    if (reset) {
      _page = 0;
      _products = [];
    }

    _isLoading = true;
    notifyListeners();

    try {
      final dbConditions = _selectedConditions.map((cond) {
        switch (cond) {
          case 'Brand New':
            return 'brandNew';
          case 'Used':
            return 'used';
          case 'Refurbished':
            return 'refurbished';
          default:
            return 'used';
        }
      }).toList();

      List<String>? campusFilter;
      if (_selectedInstitutionCode != null) {
        final inst = _institutions
            .where((i) => i.code == _selectedInstitutionCode)
            .toList();
        if (inst.isNotEmpty) {
          campusFilter = [inst.first.name];
        }
      }

      final isRandom = _sortBy == 'random';
      final result = await ProductService.getProducts(
        categoryId: _selectedCategoryId,
        searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
        conditions: dbConditions.isEmpty ? null : dbConditions,
        minPrice: _minPrice,
        maxPrice: _maxPrice,
        campuses: campusFilter,
        sortBy: isRandom ? 'newest' : _sortBy,
        offset: _page * 20,
        limit: 20,
      );

      final filtered = BlockProvider.instance.filterProducts(result);
      if (reset) {
        _products = isRandom ? _shuffled(filtered) : filtered;
      } else {
        _products = [
          ..._products,
          ...isRandom ? _shuffled(filtered) : filtered,
        ];
      }
      _hasMore = result.length >= 20;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Product> _shuffled(List<Product> items) {
    final copy = List<Product>.from(items);
    copy.shuffle();
    return copy;
  }

  void loadNextPage() {
    _page++;
    _loadProducts();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
