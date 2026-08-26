import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../services/category_image_cache_service.dart';
import '../../services/product_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/product_card.dart';
import '../../providers/block_provider.dart';
import '../../widgets/skeleton.dart';

const _maxRecentSearches = 15;

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();
  List<Category> _categories = [];
  List<Product> _searchResults = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _isLoading = false;
  Timer? _searchDebounce;
  Timer? _hintTimer;

  /// Rotating search-bar hints built from real listed product titles.
  List<String> _hintPool = [];
  int _hintIndex = 0;
  String? get _currentHint =>
      _hintPool.isEmpty ? null : _hintPool[_hintIndex % _hintPool.length];

  /// Available-listing count per category id (empty when counts are
  /// unavailable — then all categories are shown).
  final Map<String, int> _categoryCounts = {};

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadRecentSearches();
    _loadPlaceholderHints();
    _hintTimer = Timer.periodic(const Duration(milliseconds: 2800), (_) {
      if (mounted && _searchController.text.isEmpty) {
        setState(() => _hintIndex++);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _searchDebounce?.cancel();
    _hintTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final withCounts = await ProductService.getCategoriesWithProductCounts();
      final stocked = withCounts.where((c) => c.$2 > 0).toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      final list = stocked.isNotEmpty ? stocked : withCounts;
      if (mounted) {
        setState(() {
          _categories = list.map((c) => c.$1).toList();
          _categoryCounts
            ..clear()
            ..addEntries(list.map((c) => MapEntry(c.$1.id, c.$2)));
        });
      }
    } catch (_) {
      // Count embed unavailable — fall back to the plain category list.
      try {
        final categories = await ProductService.getCategories();
        if (mounted) {
          setState(() {
            _categories = categories;
            _categoryCounts.clear();
          });
        }
      } catch (_) {}
    }
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList('recent_searches') ?? [];
      if (mounted) setState(() => _recentSearches = raw);
    } catch (_) {}
  }

  /// Builds the rotating hint pool from titles of products actually listed
  /// on the marketplace.
  Future<void> _loadPlaceholderHints() async {
    try {
      final activeProducts = await ProductService.getProducts(limit: 40);
      final names = activeProducts
          .map((p) => _cleanHint(p.title))
          .whereType<String>()
          .toSet()
          .toList()
        ..shuffle();
      if (mounted && names.isNotEmpty) {
        setState(() => _hintPool = names.take(12).toList());
      }
    } catch (_) {
      // Hints are decorative — leave the pool empty on failure.
    }
  }

  String? _cleanHint(String title) {
    var t = title.trim();
    if (t.isEmpty) return null;
    if (t.length > 28) {
      t = t.split(RegExp(r'\s+')).take(3).join(' ');
      if (t.length > 28) t = t.substring(0, 28);
    }
    return t;
  }

  Future<void> _saveRecentSearch(String query) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final updated = [query, ..._recentSearches.where((s) => s != query)]
          .take(_maxRecentSearches)
          .toList();
      await prefs.setStringList('recent_searches', updated);
      if (mounted) setState(() => _recentSearches = updated);
    } catch (_) {}
  }

  Future<void> _clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('recent_searches');
      if (mounted) setState(() => _recentSearches = []);
    } catch (_) {}
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 2) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(trimmed);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isLoading = true);
    try {
      final results = await ProductService.getProducts(
        searchQuery: query,
        limit: 50,
      );
      final filtered = BlockProvider.instance.filterProducts(results);
      if (mounted) {
        setState(() {
          _searchResults = filtered;
          _isSearching = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _submitSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      final hint = _currentHint;
      if (hint != null) {
        _searchController.text = hint;
        _saveRecentSearch(hint);
        _performSearch(hint);
      }
    } else if (trimmed.length >= 2) {
      _saveRecentSearch(trimmed);
      _performSearch(trimmed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      type: ResponsiveLayoutType.general,
      backgroundColor: AppTheme.cleanBackground,
      child: SafeArea(
        child: Column(
          children: [
            _buildGlassSearchHeader(),
            Expanded(
              child: _isSearching
                  ? _buildSearchResults()
                  : _buildDefaultContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassSearchHeader() {
    return Padding(
      padding: EdgeInsets.fromLTRB(context.rw(12), context.rh(8), context.rw(12), 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.rr(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: AppTheme.glassBlurLight,
            sigmaY: AppTheme.glassBlurLight,
          ),
          child: Container(
            decoration: AppTheme.glassDecoration(radius: context.rr(16)),
            padding: EdgeInsets.symmetric(horizontal: context.rw(4), vertical: context.rw(4)),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(LucideIcons.arrowLeft, size: context.ri(20)),
                  onPressed: () => Navigator.of(context).pop(),
                  color: AppTheme.charcoalInk,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        autofocus: true,
                        style: TextStyle(
                          fontSize: context.rsp(15),
                          color: AppTheme.charcoalInk,
                        ),
                        decoration: InputDecoration(
                          hintStyle: TextStyle(
                            color: AppTheme.mutedSteel,
                            fontSize: context.rsp(15),
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: context.rh(10)),
                          prefixIcon: Padding(
                            padding: EdgeInsets.only(left: context.rw(4), right: context.rw(8)),
                            child: Icon(LucideIcons.search, size: context.ri(20), color: AppTheme.mutedSteel),
                          ),
                          prefixIconConstraints: BoxConstraints(minWidth: context.rw(32), minHeight: context.rh(24)),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(LucideIcons.x, size: context.ri(18), color: AppTheme.mutedSteel),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _isSearching = false;
                                      _searchResults = [];
                                    });
                                  },
                                )
                              : null,
                        ),
                        onChanged: (value) {
                          setState(() {});
                          _onSearchChanged(value);
                        },
                        onSubmitted: _submitSearch,
                      ),
                      // Rotating product-name hint, e-commerce style
                      if (_searchController.text.isEmpty)
                        IgnorePointer(
                          child: Padding(
                            padding: EdgeInsets.only(left: context.rw(40), right: context.rw(40)),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 450),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                layoutBuilder: (currentChild, previousChildren) {
                                  return Stack(
                                    alignment: Alignment.centerLeft,
                                    clipBehavior: Clip.none,
                                    children: [
                                      ...previousChildren,
                                      ?currentChild,
                                    ],
                                  );
                                },
                                transitionBuilder: (child, animation) {
                                  final slide = Tween<Offset>(
                                    begin: const Offset(0, 0.8),
                                    end: Offset.zero,
                                  ).animate(animation);
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(position: slide, child: child),
                                  );
                                },
                                child: _currentHint == null
                                    ? Text(
                                        'Search products...',
                                        key: const ValueKey('default-hint'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppTheme.mutedSteel,
                                          fontSize: context.rsp(15),
                                        ),
                                      )
                                    : Text(
                                        'Try "${_currentHint!}"',
                                        key: ValueKey(_currentHint),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: AppTheme.mutedSteel,
                                          fontSize: context.rsp(15),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultContent() {
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadCategories(),
          _loadRecentSearches(),
          _loadPlaceholderHints(),
        ]);
      },
      child: ListView(
      padding: EdgeInsets.fromLTRB(context.rw(12), context.rh(16), context.rw(12), context.rh(100)),
      children: [
        // Recent searches
        if (_recentSearches.isNotEmpty) ...[
          _buildRecentSearchesSection(),
          SizedBox(height: context.rh(12)),
        ],
        // Categories
        if (_categories.isNotEmpty) ...[
          _buildCategoriesSection(),
          SizedBox(height: context.rh(12)),
        ],
        // Empty state if nothing loaded yet
        if (_categories.isEmpty && _recentSearches.isEmpty)
          Padding(
            padding: EdgeInsets.only(top: context.rh(100)),
            child: EmptyState(
              icon: LucideIcons.search,
              title: 'Search for products',
              description: 'Find what you need on your campus',
            ),
          ),
      ],
    ),
    );
  }

  Widget _buildRecentSearchesSection() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(context.rr(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppTheme.glassBlurLight,
          sigmaY: AppTheme.glassBlurLight,
        ),
        child: Container(
          decoration: AppTheme.glassDecoration(radius: context.rr(16)),
          padding: EdgeInsets.all(context.rw(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.clock, size: context.ri(18), color: AppTheme.mutedSteel),
                  SizedBox(width: context.rw(8)),
                  Text(
                    'Recent Searches',
                    style: TextStyle(
                      fontSize: context.rsp(16),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _clearRecentSearches,
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: context.rsp(13),
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.rh(12)),
              Wrap(
                spacing: context.rw(8),
                runSpacing: context.rh(8),
                children: _recentSearches.take(8).map((term) {
                  return GestureDetector(
                    onTap: () {
                      _searchController.text = term;
                      _submitSearch(term);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.rw(12),
                        vertical: context.rh(8),
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.glassSurfaceLight,
                        borderRadius: BorderRadius.circular(context.rr(20)),
                        border: Border.all(color: AppTheme.glassBorder, width: 0.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(LucideIcons.search, size: context.ri(14), color: AppTheme.mutedSteel),
                          SizedBox(width: context.rw(6)),
                          Text(
                            term,
                            style: TextStyle(
                              fontSize: context.rsp(13),
                              color: AppTheme.charcoalInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoriesSection() {
    if (_categories.isEmpty) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: BorderRadius.circular(context.rr(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: AppTheme.glassBlurLight,
          sigmaY: AppTheme.glassBlurLight,
        ),
        child: Container(
          decoration: AppTheme.glassDecoration(radius: context.rr(16)),
          padding: EdgeInsets.all(context.rw(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.grid3x3, size: context.ri(18), color: AppTheme.charcoalInk),
                  SizedBox(width: context.rw(8)),
                  Text(
                    'Categories',
                    style: TextStyle(
                      fontSize: context.rsp(16),
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.rh(12)),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.8,
                ),
                itemCount: _categories.length > 10 ? 10 : _categories.length,
                itemBuilder: (context, index) {
                  final category = _categories[index];
                  final color = Color(
                    AppTheme.categoryColors[category.colorIndex % AppTheme.categoryColors.length],
                  );
                  final count = _categoryCounts[category.id] ?? 0;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).pushNamed('/explore', arguments: category.id),
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(context.rr(12)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: category.imageUrl != null
                          ? Stack(
                              fit: StackFit.expand,
                              children: [
                                CachedNetworkImage(
                                  imageUrl: category.imageUrl!,
                                  cacheManager: CategoryImageCacheManager(),
                                  fit: BoxFit.cover,
                                  fadeInDuration: const Duration(milliseconds: 150),
                                  placeholder: (_, _) =>
                                      _buildCategoryFallback(category, color),
                                  errorWidget: (_, _, _) =>
                                      _buildCategoryFallback(category, color),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black.withValues(alpha: 0.1),
                                        Colors.black.withValues(alpha: 0.6),
                                      ],
                                      stops: const [0.4, 1.0],
                                    ),
                                  ),
                                ),
                                if (count > 0)
                                  Positioned(
                                    top: context.rh(5),
                                    right: context.rw(5),
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: context.rw(6),
                                        vertical: context.rh(2),
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(context.rr(8)),
                                      ),
                                      child: Text(
                                        count > 99 ? '99+' : '$count',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: context.rsp(9),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  left: context.rw(10),
                                  right: context.rw(10),
                                  bottom: context.rh(6),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.bottomLeft,
                                    child: Text(
                                      category.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.2,
                                        shadows: const [
                                          Shadow(blurRadius: 4, color: Colors.black54),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Padding(
                              padding: EdgeInsets.symmetric(horizontal: context.rw(12), vertical: context.rh(8)),
                              child: Row(
                                children: [
                                  Icon(
                                    _getCategoryIcon(category.icon),
                                    size: context.ri(20),
                                    color: color,
                                  ),
                                  SizedBox(width: context.rw(8)),
                                  Expanded(
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        category.name,
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.charcoalInk,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (count > 0) ...[
                                    SizedBox(width: context.rw(4)),
                                    Text(
                                      count > 99 ? '99+' : '$count',
                                      style: TextStyle(
                                        fontSize: context.rsp(10),
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.mutedSteel,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryFallback(Category category, Color color) {
    return Container(
      color: color.withValues(alpha: 0.15),
      child: Center(
        child: Icon(
          _getCategoryIcon(category.icon),
          size: context.ri(24),
          color: color,
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: ProductGridSkeleton(count: 6),
      );
    }
    if (_searchResults.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _performSearch(_searchController.text.trim()),
        child: ListView(
          children: [
            SizedBox(height: context.rh(100)),
            EmptyState(
              icon: LucideIcons.searchX,
              title: 'No products found',
              description: 'Try a different search term',
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _performSearch(_searchController.text.trim()),
      child: GridView.builder(
      padding: EdgeInsets.fromLTRB(context.rw(12), context.rh(12), context.rw(12), context.rh(100)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: context.isDesktop ? 4 : (context.isTablet ? 3 : 2),
        mainAxisSpacing: context.rh(12),
        crossAxisSpacing: context.rw(12),
        childAspectRatio: 0.72,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final product = _searchResults[index];
        return ProductCard(
          product: product,
          onTap: () {
            if (_searchController.text.trim().isNotEmpty) {
              _saveRecentSearch(_searchController.text.trim());
            }
            Navigator.of(context).pushNamed('/product', arguments: product.id);
          },
        );
      },
      ),
    );
  }
}

IconData _getCategoryIcon(String? icon) {
  switch (icon) {
    case 'book':
      return LucideIcons.bookOpen;
    case 'shirt':
      return LucideIcons.shirt;
    case 'dumbbell':
      return LucideIcons.dumbbell;
    case 'music':
      return LucideIcons.music;
    case 'gamepad':
      return LucideIcons.gamepad2;
    case 'home':
      return LucideIcons.home;
    case 'car':
      return LucideIcons.car;
    case 'coffee':
      return LucideIcons.coffee;
    case 'video':
      return LucideIcons.video;
    case 'code':
      return LucideIcons.code;
    case 'wrench':
      return LucideIcons.wrench;
    case 'armchair':
      return LucideIcons.armchair;
    case 'grid':
    default:
      return LucideIcons.grid3x3;
  }
}
