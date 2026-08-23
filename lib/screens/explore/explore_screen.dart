import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../models/institution_model.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../providers/providers.dart';
import '../../services/institution_service.dart';
import '../../services/product_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/purchase_access.dart';
import '../../utils/responsive.dart';
import '../../widgets/adaptive_nav.dart';
import '../../widgets/animated_press.dart';
import '../../widgets/user_avatar_menu.dart';
import '../../widgets/verification_badge.dart';
import '../../widgets/discount_countdown.dart';
import '../../widgets/skeleton.dart';
import '../../widgets/empty_state.dart';
import '../../utils/formatters.dart';
import '../../widgets/responsive_layout.dart';

const _exploreConditions = ['Brand New', 'Used', 'Refurbished'];

class ExploreScreen extends ConsumerStatefulWidget {
  final String? initialCategoryId;

  const ExploreScreen({super.key, this.initialCategoryId});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
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

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocusNode = FocusNode();
  final _overlayKey = GlobalKey();

  /// Top gap between the screen top and the product grid. Measured from the
  /// floating header/search overlay so cards never sit under the search bar.
  double _gridTopPadding = 120;

  List<Product> _searchSuggestions = [];
  final Map<String, int> _viewCounts = {};
  bool _showSuggestions = false;
  bool _showScrollToTop = false;
  Timer? _searchDebounce;
  Timer? _realtimeDebounce;
  bool _isFetching = false;
  ProviderSubscription<List<Product>>? _providerProductsSub;
  ProviderSubscription<List<Category>>? _providerCategoriesSub;

  @override
  void initState() {
    super.initState();
    _selectedCategoryId = widget.initialCategoryId;
    _loadCategories();
    _loadBusinessName();
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        setState(() => _showSuggestions = false);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGridTopPadding());
    // React to realtime product/category changes pushed by productProvider
    // so the grid updates without leaving and re-entering the screen.
    _providerProductsSub = ref.listenManual(
      productProvider.select((p) => p.products),
      (previous, next) => _scheduleRealtimeRefresh(),
    );
    _providerCategoriesSub = ref.listenManual(
      productProvider.select((p) => p.categories),
      (previous, next) => _loadCategories(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(cartProvider).loadCart();
      ref.read(walletProvider).loadWallet();
      ref.read(productProvider).loadFavoriteIds();
      // Load institutions first, then set default institution and load products
      _loadInstitutions().then((_) {
        final user = ref.read(authProvider).user;
        if (user?.university != null && user!.university!.isNotEmpty) {
          final match = _institutions.where((i) => i.name.toLowerCase() == user.university!.toLowerCase()).toList();
          if (match.isNotEmpty && mounted) {
            setState(() => _selectedInstitutionCode = match.first.code);
          }
        }
        // Load products once after institutions are ready
        if (mounted) {
          _loadProducts();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-measure when status bar / text scale / orientation changes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateGridTopPadding());
  }

  /// Measures the floating header/search overlay and keeps the grid padding
  /// below it (plus a small gap).
  void _updateGridTopPadding() {
    final overlayHeight = _overlayKey.currentContext?.size?.height ?? 0;
    if (overlayHeight <= 0 || !mounted) return;
    final newPadding = overlayHeight + 12;
    if ((newPadding - _gridTopPadding).abs() > 0.5) {
      setState(() => _gridTopPadding = newPadding);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await ProductService.getCategories();
      if (mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _loadBusinessName() async {
    try {
      final uid = SupabaseService.instance.currentUser?.id;
      if (uid == null) return;
      final data = await SupabaseService.table('business_profiles')
          .select('business_name')
          .eq('seller_id', uid)
          .maybeSingle();
      if (mounted && data != null) {
        setState(() => _businessName = data['business_name'] as String?);
      }
    } catch (_) {}
  }

  Future<void> _loadInstitutions() async {
    try {
      final institutions = await InstitutionService.getInstitutionsWithCounts();
      if (mounted) {
        setState(() {
          _institutions = institutions;
        });
      }
    } catch (e) {
      // Fallback to basic list if RPC fails
      try {
        final institutions = await InstitutionService.getInstitutions();
        if (mounted) {
          setState(() {
            _institutions = institutions;
          });
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _searchDebounce?.cancel();
    _realtimeDebounce?.cancel();
    _providerProductsSub?.close();
    _providerCategoriesSub?.close();
    super.dispose();
  }

  /// Debounced silent refresh when products change in realtime.
  void _scheduleRealtimeRefresh() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 800), () {
      if (mounted) _loadProducts(reset: true, silent: true);
    });
  }

  void _onScroll() {
    final position = _scrollController.position;
    final show = position.pixels > 400;
    if (show != _showScrollToTop) {
      setState(() => _showScrollToTop = show);
    }
    if (position.pixels >= position.maxScrollExtent * 0.8 &&
        _hasMore &&
        !_isFetching) {
      setState(() => _page++);
      _loadProducts();
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _searchDebounce?.cancel();
    if (query.isEmpty) {
      setState(() {
        _showSuggestions = false;
        _searchSuggestions = [];
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadSuggestions(query);
    });
  }

  Future<void> _loadSuggestions(String query) async {
    try {
      final results = await ProductService.getProducts(
        searchQuery: query,
        limit: 5,
      );
      if (mounted) {
        setState(() {
          _searchSuggestions = results;
          _showSuggestions = results.isNotEmpty;
        });
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _loadProducts({bool reset = false, bool silent = false}) async {
    if (_isFetching && silent) return;
    _isFetching = true;
    if (reset) {
      setState(() {
        _page = 0;
        // Silent refreshes swap the grid in place once data arrives so the
        // current content doesn't flash empty.
        if (!silent) _products.clear();
      });
    }

    if (!silent) setState(() => _isLoading = true);

    try {
      final dbConditions = _selectedConditions.map((cond) {
        switch (cond) {
          case 'Brand New': return 'brandNew';
          case 'Used': return 'used';
          case 'Refurbished': return 'refurbished';
          default: return 'used';
        }
      }).toList();

      // Build campus filter from selected institution
      List<String>? campusFilter;
      if (_selectedInstitutionCode != null) {
        final inst = _institutions.where((i) => i.code == _selectedInstitutionCode).toList();
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
      if (mounted) {
        setState(() {
          if (reset) {
            _products = isRandom ? _shuffled(result) : result;
          } else {
            _products.addAll(isRandom ? _shuffled(result) : result);
          }
          _hasMore = result.length >= 20;
          if (!silent) _isLoading = false;
        });
        unawaited(_loadViewCounts());
      }
    } catch (e) {
      if (mounted && !silent) setState(() => _isLoading = false);
    } finally {
      _isFetching = false;
    }
  }

  List<Product> _shuffled(List<Product> items) {
    final copy = List<Product>.from(items);
    copy.shuffle();
    return copy;
  }

  /// Fetches total views for the loaded products (same source as the
  /// product detail page).
  Future<void> _loadViewCounts() async {
    final ids = _products.map((p) => p.id).toList();
    if (ids.isEmpty) return;
    final counts = await ProductService.getViewCounts(ids);
    if (!mounted || counts.isEmpty) return;
    setState(() => _viewCounts.addAll(counts));
  }

  void _applyFilters() {
    Navigator.of(context).pop();
    _loadProducts(reset: true);
  }

  void _requireAuth(BuildContext context, VoidCallback callback) {
    final auth = ref.read(authProvider);
    if (auth.isAuthenticated) {
      callback();
    } else {
      Navigator.of(context).pushNamed('/login');
    }
  }

  void _showInstitutionPicker(BuildContext context) {
    final totalProducts = _institutions.fold<int>(0, (sum, i) => sum + i.productCount);
    final searchCtrl = TextEditingController();

    showShadSheet(
      context: context,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            final query = searchCtrl.text.toLowerCase();
            final filtered = query.isEmpty
                ? _institutions
                : _institutions.where((i) =>
                    i.code.toLowerCase().contains(query) ||
                    i.name.toLowerCase().contains(query) ||
                    (i.location?.toLowerCase().contains(query) ?? false)).toList();

            return ShadSheet(
              title: const Text('Select Institution'),
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: SizedBox(
                  height: 450,
                  child: Material(
                  color: Colors.transparent,
                  child: Column(
                    children: [
                      // Search field
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ShadInput(
                          controller: searchCtrl,
                          placeholder: const Text('Search institutions...'),
                          leading: const Padding(
                            padding: EdgeInsets.only(left: 12, right: 8),
                            child: Icon(LucideIcons.search, size: 18),
                          ),
                          onChanged: (_) => setSheetState(() {}),
                        ),
                      ),
                      Expanded(
                        child: ListView(
                          children: [
                            // All Institutions option (only when not searching)
                            if (query.isEmpty)
                              ListTile(
                                leading: const Icon(LucideIcons.building2, color: AppTheme.accent),
                                title: const Text('All Institutions'),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '$totalProducts',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.accent),
                                  ),
                                ),
                                selected: _selectedInstitutionCode == null,
                                selectedTileColor: AppTheme.accent.withValues(alpha: 0.05),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                onTap: () {
                                  Navigator.of(sheetCtx).pop();
                                  if (_selectedInstitutionCode != null) {
                                    setState(() => _selectedInstitutionCode = null);
                                    _loadProducts(reset: true);
                                  }
                                },
                              ),
                            if (query.isEmpty) const Divider(),
                            // Empty state
                            if (filtered.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(24),
                                child: Center(
                                  child: Text('No institutions found', style: TextStyle(color: AppTheme.mutedSteel)),
                                ),
                              ),
                            // Filtered institutions
                            ...filtered.map((inst) {
                              return ListTile(
                                leading: inst.logoUrl != null
                                    ? CachedNetworkImage(
                                        imageUrl: inst.logoUrl!,
                                        width: 24,
                                        height: 24,
                                        fit: BoxFit.contain,
                                        memCacheWidth: 24,
                                        errorWidget: (_, _, _) => const Icon(LucideIcons.graduationCap, size: 20, color: AppTheme.accent),
                                      )
                                    : const Icon(LucideIcons.graduationCap, size: 20, color: AppTheme.accent),
                                title: Text(inst.code),
                                subtitle: Text(inst.name),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: inst.productCount > 0
                                        ? AppTheme.accent.withValues(alpha: 0.1)
                                        : AppTheme.mutedSteel.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${inst.productCount}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: inst.productCount > 0 ? AppTheme.accent : AppTheme.mutedSteel,
                                    ),
                                  ),
                                ),
                                selected: _selectedInstitutionCode == inst.code,
                                selectedTileColor: AppTheme.accent.withValues(alpha: 0.05),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                onTap: () {
                                  Navigator.of(sheetCtx).pop();
                                  if (_selectedInstitutionCode != inst.code) {
                                    setState(() => _selectedInstitutionCode = inst.code);
                                    _loadProducts(reset: true);
                                  }
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(exploreRefreshProvider, (previous, next) {
      _loadProducts(reset: true);
    });

    final auth = ref.watch(authProvider);
    final cart = ref.watch(cartProvider);
    final cartCount = cart.itemCount;
    return ResponsiveLayout(
      type: ResponsiveLayoutType.general,
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      bottomNavigationBar: const AdaptiveNav(currentIndex: 1),
      child: Stack(
        children: [
          // Scrollable product grid that extends behind the header/search
          Positioned.fill(
            child: _isLoading && _products.isEmpty
                ? Padding(
                    padding: EdgeInsets.fromLTRB(12, _gridTopPadding, 12, 100),
                    child: const ProductGridSkeleton(count: 6),
                  )
                : _products.isEmpty
                    ? Padding(
                        padding: EdgeInsets.only(top: _gridTopPadding),
                        child: _buildEmptyState(),
                      )
                    : RefreshIndicator(
                        onRefresh: () => _loadProducts(reset: true),
                        child: GridView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(12, _gridTopPadding, 12, 100),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: context.isDesktop
                                ? 4
                                : (context.isTablet ? 3 : 2),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.72,
                          ),
                          itemCount: _products.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _products.length) {
                              return const ProductCardSkeleton();
                            }
                            return _buildProductCard(_products[index]);
                          },
                        ),
                      ),
          ),
          // Floating overlay: header + search bar (transparent gap between them)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Column(
              key: _overlayKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Floating glass header
                Padding(
                  padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + 8, 12, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: AppTheme.glassBlur, sigmaY: AppTheme.glassBlur),
                      child: Container(
                        decoration: AppTheme.glassDecoration(radius: 20),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        child: Row(
                          children: [
                            // Institution filter dropdown
                            Expanded(
                              child: GestureDetector(
                                onTap: () => _showInstitutionPicker(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.glassSurfaceLight,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppTheme.glassBorder),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_selectedInstitutionCode != null) ...[
                                        Builder(
                                          builder: (context) {
                                            final inst = _institutions.where((i) => i.code == _selectedInstitutionCode).toList();
                                            if (inst.isEmpty) return const SizedBox.shrink();
                                            return inst.first.logoUrl != null
                                                ? Padding(
                                                    padding: const EdgeInsets.only(right: 8),
                                                    child: CachedNetworkImage(
                                                      imageUrl: inst.first.logoUrl!,
                                                      width: 20,
                                                      height: 20,
                                                      fit: BoxFit.contain,
                                                      memCacheWidth: 20,
                                                      errorWidget: (_, _, _) => const Icon(LucideIcons.graduationCap, size: 16, color: AppTheme.accent),
                                                    ),
                                                  )
                                                : const Padding(
                                                    padding: EdgeInsets.only(right: 8),
                                                    child: Icon(LucideIcons.graduationCap, size: 16, color: AppTheme.accent),
                                                  );
                                          },
                                        ),
                                      ] else
                                        const Padding(
                                          padding: EdgeInsets.only(right: 8),
                                          child: Icon(LucideIcons.building2, size: 16, color: AppTheme.accent),
                                        ),
                                      Flexible(
                                        child: Text(
                                          _selectedInstitutionCode != null
                                              ? (_institutions.where((i) => i.code == _selectedInstitutionCode).map((i) => i.name).firstOrNull ?? _selectedInstitutionCode!)
                                              : 'All Institutions',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: _selectedInstitutionCode != null ? AppTheme.charcoalInk : AppTheme.mutedSteel,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.only(left: 4),
                                        child: Icon(LucideIcons.chevronDown, size: 16, color: AppTheme.mutedSteel),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Row(
                              children: [
                                BadgeIconButton(
                                  icon: LucideIcons.shoppingCart,
                                  count: cartCount,
                                  activeColor: AppTheme.accent,
                                  onPressed: () => _requireAuth(context, () => Navigator.of(context).pushNamed('/cart')),
                                ),
                                Builder(
                                  builder: (context) {
                                    final unreadNotifs = ref.watch(messageProvider).unreadNotificationsCount;
                                    return BadgeIconButton(
                                      icon: LucideIcons.bell,
                                      count: unreadNotifs,
                                      activeColor: AppTheme.accent,
                                      onPressed: () => _requireAuth(context, () => Navigator.of(context).pushNamed('/notifications')),
                                    );
                                  },
                                ),
                                UserAvatarMenu(
                                  avatarUrl: auth.user?.avatarUrl,
                                  fullName: auth.user?.fullName,
                                  businessName: _businessName,
                                  isVerified: auth.user?.isVerified == true,
                                  isAuthenticated: auth.isAuthenticated,
                                  onLoginTap: () => Navigator.of(context).pushNamed('/login'),
                                  onWishlistTap: () => Navigator.of(context).pushNamed('/wishlist'),
                                  onOrdersTap: () => Navigator.of(context).pushNamed('/orders'),
                                  onWalletTap: () => Navigator.of(context).pushNamed('/wallet'),
                                  onFollowingTap: () => Navigator.of(context).pushNamed('/following'),
                                  onSettingsTap: () => Navigator.of(context).pushNamed('/account'),
                                  onSignOut: () async {
                                    await auth.signOut();
                                    if (context.mounted) {
                                    unawaited(Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false));
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Floating glass search bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: AppTheme.glassBlurLight, sigmaY: AppTheme.glassBlurLight),
                      child: Container(
                        decoration: AppTheme.glassDecoration(radius: 16),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: ShadInput(
                                controller: _searchController,
                                focusNode: _searchFocusNode,
                                placeholder: const Text('Search products...'),
                                leading: const Padding(
                                  padding: EdgeInsets.only(left: 8),
                                  child: Icon(LucideIcons.search, size: 20, color: AppTheme.mutedSteel),
                                ),
                                trailing: _searchController.text.isNotEmpty
                                    ? ShadIconButton.ghost(
                                        icon: const Icon(LucideIcons.x, size: 18, color: AppTheme.mutedSteel),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() {
                                            _searchQuery = '';
                                            _showSuggestions = false;
                                            _searchSuggestions = [];
                                          });
                                          _loadProducts(reset: true);
                                        },
                                      )
                                    : null,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (value) {
                                  setState(() {
                                    _searchQuery = value;
                                    _showSuggestions = false;
                                  });
                                  _loadProducts(reset: true);
                                },
                                onChanged: (value) {
                                  setState(() => _searchQuery = value);
                                  if (value.length >= 2) {
                                    _loadSuggestions(value);
                                  } else {
                                    setState(() {
                                      _showSuggestions = false;
                                      _searchSuggestions = [];
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            ShadIconButton.ghost(
                              icon: const Icon(LucideIcons.slidersHorizontal, size: 20, color: AppTheme.mutedSteel),
                              onPressed: () => _showFilterSheet(context),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Search suggestions dropdown
          if (_showSuggestions)
            Positioned(
              left: 12,
              right: 12,
              top: _gridTopPadding,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(12),
                color: AppTheme.pureSurface,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.35,
                  ),
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: _searchSuggestions.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 12, endIndent: 12),
                    itemBuilder: (ctx, i) {
                      return _buildSuggestionTile(_searchSuggestions[i]);
                    },
                  ),
                ),
              ),
            ),
          // Scroll to top button (raised above the floating bottom nav pill)
          if (_showScrollToTop)
            Positioned(
              right: 16,
              bottom: 100,
              child: FloatingActionButton.small(
                onPressed: () {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                  );
                },
                backgroundColor: AppTheme.pureSurface,
                foregroundColor: AppTheme.accent,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppTheme.whisperBorder),
                ),
                child: const Icon(LucideIcons.arrowUp, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final cart = ref.watch(cartProvider);
    final productProv = ref.watch(productProvider);
    final authProv = ref.watch(authProvider);
    final inCart = cart.isInCart(product.id);
    final hasDiscount = product.isDiscountActive;
    final isFavorited = productProv.isFavorited(product.id);
    final viewCount = _viewCounts[product.id] ?? 0;

    return AnimatedPress(
      onTap: () => Navigator.of(context).pushNamed('/product', arguments: product.id),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(16)),
          border: Border.all(
            color: inCart ? AppTheme.accent : AppTheme.whisperBorder,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                children: [
                  if (product.effectiveThumbnail != null)
                    CachedNetworkImage(
                      imageUrl: product.effectiveThumbnail!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 160,
                      placeholder: (_, _) => Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.warmMist,
                        child: Icon(LucideIcons.image, color: AppTheme.mutedSteel, size: context.ri(24)),
                      ),
                    )
                  else
                    Container(
                      color: AppTheme.warmMist,
                      child: Icon(LucideIcons.image, color: AppTheme.mutedSteel, size: context.ri(24)),
                    ),
                  if (inCart)
                    Positioned(
                      top: context.rh(8),
                      left: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(context.rr(12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.shoppingCart, size: context.ri(10), color: Colors.white),
                            SizedBox(width: context.rw(4)),
                            Text(
                              'In Cart',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.rsp(10),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Rating badge on thumbnail
                  if (product.averageRating != null && product.averageRating! > 0)
                    Positioned(
                      top: context.rh(inCart ? 36 : 8),
                      left: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(6), vertical: context.rh(3)),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(context.rr(10)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: context.ri(10), color: const Color(0xFFFFD700)),
                            SizedBox(width: context.rw(3)),
                            Text(
                              product.averageRating!.toStringAsFixed(1),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.rsp(10),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (product.reviewCount != null && product.reviewCount! > 0) ...[
                              SizedBox(width: context.rw(2)),
                              Text(
                                '(${product.reviewCount})',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: context.rsp(9),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  // Wishlist heart
                  Positioned(
                    top: context.rh(6),
                    right: context.rw(6),
                    child: GestureDetector(
                      onTap: () => _requireAuth(context, () {
                        productProv.toggleFavorite(product.id);
                      }),
                      child: Container(
                        padding: EdgeInsets.all(context.rw(6)),
                        decoration: BoxDecoration(
                          color: isFavorited ? AppTheme.destructive : Colors.black26,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          LucideIcons.heart,
                          size: context.ri(16),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (hasDiscount)
                    Positioned(
                      top: context.rh(44),
                      right: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
                        decoration: BoxDecoration(
                          color: AppTheme.destructive,
                          borderRadius: BorderRadius.circular(context.rr(12)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '-${product.discountPercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.rsp(10),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (product.discountEndDate != null) ...[
                              SizedBox(height: context.rh(1)),
                              DiscountCountdown(
                                endDate: product.discountEndDate,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: context.rsp(8),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (product.hasVideo)
                    Positioned(
                      bottom: context.rh(8),
                      left: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.all(context.rw(6)),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(LucideIcons.play, size: context.ri(12), color: Colors.white),
                      ),
                    ),
                  if (product.status != ProductStatus.available)
                    Positioned(
                      top: context.rh(8),
                      left: inCart ? context.rw(8) : null,
                      right: inCart ? null : context.rw(8),
                      bottom: hasDiscount ? context.rh(8) : null,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
                        decoration: BoxDecoration(
                          color: product.status == ProductStatus.sold
                              ? AppTheme.destructive
                              : AppTheme.warningAmber,
                          borderRadius: BorderRadius.circular(context.rr(12)),
                        ),
                        child: Text(
                          product.status.displayName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.rsp(10),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  // Add to cart button (hidden for own products and for
                  // cross-institution listings the buyer has no access to)
                  if (!inCart &&
                      product.sellerId != authProv.user?.id &&
                      product.status == ProductStatus.available &&
                      !PurchaseAccess.isRestrictedForBuyer(
                        campuses: product.campuses,
                        userUniversity: authProv.user?.university,
                      ))
                    Positioned(
                      bottom: context.rh(8),
                      right: context.rw(8),
                      child: GestureDetector(
                        onTap: () {
                          ref.read(cartProvider).addToCart(
                            productId: product.id,
                            title: product.title,
                            price: product.effectivePrice,
                            thumbnail: product.effectiveThumbnail,
                            sellerId: product.sellerId,
                            sellerName: product.sellerName,
                            campuses: product.campuses,
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.all(context.rw(8)),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.plus,
                            size: context.ri(18),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.rw(6), vertical: context.rh(4)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.rsp(12),
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                    const Spacer(),
                    // Price + total views
                    Row(
                      children: [
                        Expanded(
                          child: hasDiscount
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      formatGhs(product.effectivePrice),
                                      style: TextStyle(
                                        fontSize: context.rsp(14),
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.destructive,
                                      ),
                                    ),
                                    Text(
                                      formatGhs(product.price),
                                      style: TextStyle(
                                        fontSize: context.rsp(10),
                                        color: AppTheme.mutedSteel,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  formatGhs(product.price),
                                  style: TextStyle(
                                    fontSize: context.rsp(14),
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.charcoalInk,
                                  ),
                                ),
                        ),
                        if (viewCount > 0) ...[
                          Icon(LucideIcons.eye, size: context.ri(11), color: AppTheme.mutedSteel),
                          SizedBox(width: context.rw(3)),
                          Text(
                            '$viewCount',
                            style: TextStyle(
                              fontSize: context.rsp(10),
                              color: AppTheme.mutedSteel,
                            ),
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: context.rh(2)),
                    // Seller info
                    if (product.sellerName != null)
                      Row(
                        children: [
                          ShadAvatar(
                            product.sellerAvatar?.isNotEmpty == true ? product.sellerAvatar : null,
                            size: Size(context.ri(16), context.ri(16)),
                            backgroundColor: AppTheme.accent,
                            placeholder: Text(
                              (product.businessName ?? product.sellerName ?? 'S')[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: context.rsp(7),
                              ),
                            ),
                          ),
                          SizedBox(width: context.rw(3)),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    product.businessName ?? product.sellerName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: context.rsp(9),
                                      color: AppTheme.mutedSteel,
                                    ),
                                  ),
                                ),
                                if (product.isSellerVerified) ...[
                                  SizedBox(width: context.rw(2)),
                                  VerificationBadge(size: context.ri(10)),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: LucideIcons.package,
      title: 'No products found',
      description: 'Try adjusting your search or filters.',
      actionLabel: 'Clear Filters',
      onActionPressed: () {
        setState(() {
          _searchQuery = '';
          _selectedCategoryId = null;
          _selectedConditions = [];
          _minPrice = null;
          _maxPrice = null;
        });
        _loadProducts(reset: true);
      },
    );
  }

  Widget _buildSuggestionTile(Product product) {
    return InkWell(
      onTap: () {
        setState(() => _showSuggestions = false);
        _searchFocusNode.unfocus();
        Navigator.of(context).pushNamed('/product', arguments: product.id);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 40,
                height: 40,
                child: product.effectiveThumbnail != null
                    ? CachedNetworkImage(
                        imageUrl: product.effectiveThumbnail!,
                        fit: BoxFit.cover,
                        memCacheWidth: 40,
                        placeholder: (_, _) => Container(color: AppTheme.warmMist),
                        errorWidget: (_, _, _) => Container(
                          color: AppTheme.warmMist,
                          child: const Icon(LucideIcons.image, size: 20, color: AppTheme.mutedSteel),
                        ),
                      )
                    : Container(
                        color: AppTheme.warmMist,
                        child: const Icon(LucideIcons.image, size: 20, color: AppTheme.mutedSteel),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.charcoalInk,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatGhs(product.price),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (product.isSellerVerified)
              Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: AppTheme.successMoss,
                  shape: BoxShape.circle,
                ),
                child: const Icon(LucideIcons.check, color: Colors.white, size: 10),
              ),
          ],
        ),
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    showShadSheet(
      context: context,
      builder: (ctx) => ShadSheet(
        title: const Text('Filters'),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: _FilterSheet(
          categories: _categories,
          selectedCategoryId: _selectedCategoryId,
          selectedConditions: _selectedConditions,
          minPrice: _minPrice,
          maxPrice: _maxPrice,
          sortBy: _sortBy,
          onCategoryChanged: (v) => _selectedCategoryId = v,
          onConditionsChanged: (v) => _selectedConditions = v,
          onMinPriceChanged: (v) => _minPrice = v,
          onMaxPriceChanged: (v) => _maxPrice = v,
          onSortChanged: (v) => _sortBy = v,
          onApply: _applyFilters,
        ),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final List<Category> categories;
  final String? selectedCategoryId;
  final List<String> selectedConditions;
  final double? minPrice;
  final double? maxPrice;
  final String sortBy;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<List<String>> onConditionsChanged;
  final ValueChanged<double?> onMinPriceChanged;
  final ValueChanged<double?> onMaxPriceChanged;
  final ValueChanged<String> onSortChanged;
  final VoidCallback onApply;

  const _FilterSheet({
    required this.categories,
    this.selectedCategoryId,
    required this.selectedConditions,
    this.minPrice,
    this.maxPrice,
    required this.sortBy,
    required this.onCategoryChanged,
    required this.onConditionsChanged,
    required this.onMinPriceChanged,
    required this.onMaxPriceChanged,
    required this.onSortChanged,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late List<String> _conditions;
  late String? _categoryId;
  late TextEditingController _minCtrl;
  late TextEditingController _maxCtrl;
  late String _sortBy;

  @override
  void initState() {
    super.initState();
    _conditions = List.from(widget.selectedConditions);
    _categoryId = widget.selectedCategoryId;
    _minCtrl = TextEditingController(text: widget.minPrice?.toStringAsFixed(0) ?? '');
    _maxCtrl = TextEditingController(text: widget.maxPrice?.toStringAsFixed(0) ?? '');
    _sortBy = widget.sortBy;
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  void _toggleCondition(String cond) {
    setState(() {
      if (_conditions.contains(cond)) {
        _conditions.remove(cond);
      } else {
        _conditions.add(cond);
      }
    });
  }

  void _showCategorySearchSheet(BuildContext context) {
    final searchCtrl = TextEditingController();
    List<Category> filtered = widget.categories;

    showShadSheet(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ShadSheet(
              title: const Text('Select Category'),
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.5,
                  child: Column(
                  children: [
                    ShadInput(
                      controller: searchCtrl,
                      placeholder: const Text('Search categories...'),
                      leading: const Icon(LucideIcons.search, size: 18),
                      onChanged: (query) {
                        setSheetState(() {
                          filtered = query.isEmpty
                              ? widget.categories
                              : widget.categories
                                  .where((c) => c.name.toLowerCase().contains(query.toLowerCase()))
                                  .toList();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Material(
                        color: Colors.transparent,
                        child: ListView(
                          children: [
                            ListTile(
                              leading: Icon(
                                _categoryId == null ? LucideIcons.checkCircle : LucideIcons.circle,
                                color: _categoryId == null ? AppTheme.accent : null,
                                size: 20,
                              ),
                              title: const Text('All Categories'),
                              selected: _categoryId == null,
                              selectedTileColor: AppTheme.accent.withValues(alpha: 0.08),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              onTap: () {
                                setState(() => _categoryId = null);
                                Navigator.of(ctx).pop();
                              },
                            ),
                            ...filtered.map((cat) => ListTile(
                            leading: Icon(
                              _categoryId == cat.id ? LucideIcons.checkCircle : LucideIcons.circle,
                              color: _categoryId == cat.id ? AppTheme.accent : null,
                              size: 20,
                            ),
                            title: Text(cat.name),
                            selected: _categoryId == cat.id,
                            selectedTileColor: AppTheme.accent.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            onTap: () {
                              setState(() => _categoryId = cat.id);
                              Navigator.of(ctx).pop();
                            },
                          )),
                        ],
                       ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            );
          },
        );
      },
    );
    searchCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.65,
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        shrinkWrap: true,
        children: [
          // Category
          const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.mutedSteel)),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showCategorySearchSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _categoryId == null
                          ? 'All Categories'
                          : (widget.categories.where((c) => c.id == _categoryId).firstOrNull?.name ?? 'All Categories'),
                      style: TextStyle(
                        color: _categoryId == null ? const Color(0xFF94A3B8) : const Color(0xFF1E293B),
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const Icon(LucideIcons.chevronDown, color: Color(0xFF64748B)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Sort
          const Text('Sort By', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.mutedSteel)),
          const SizedBox(height: 8),
          ShadSelect<String>(
            initialValue: _sortBy,
            options: const [
              ShadOption(value: 'newest', child: Text('Newest Arrivals')),
              ShadOption(value: 'price_asc', child: Text('Price: Low to High')),
              ShadOption(value: 'price_desc', child: Text('Price: High to Low')),
            ],
            onChanged: (v) => setState(() => _sortBy = v ?? 'newest'),
            selectedOptionBuilder: (context, value) => Text(
              value == 'newest'
                  ? 'Newest Arrivals'
                  : value == 'price_asc'
                      ? 'Price: Low to High'
                      : 'Price: High to Low',
            ),
          ),

          const SizedBox(height: 20),

          // Condition
          const Text('Condition', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.mutedSteel)),
          const SizedBox(height: 8),
          ..._exploreConditions.map((cond) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    ShadCheckbox(
                      value: _conditions.contains(cond),
                      onChanged: (_) => _toggleCondition(cond),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _toggleCondition(cond),
                      child: Text(cond, style: const TextStyle(fontSize: 14)),
                    ),
                  ],
                ),
              )),

          const SizedBox(height: 16),

          // Price Range
          const Text('Price Range', style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.mutedSteel)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ShadInput(
                  controller: _minCtrl,
                  placeholder: const Text('Min'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('-', style: TextStyle(color: AppTheme.mutedSteel)),
              ),
              Expanded(
                child: ShadInput(
                  controller: _maxCtrl,
                  placeholder: const Text('Max'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Apply button
          ShadButton(
            onPressed: () {
              widget.onCategoryChanged(_categoryId);
              widget.onConditionsChanged(_conditions);
              widget.onMinPriceChanged(
                _minCtrl.text.isNotEmpty ? double.tryParse(_minCtrl.text) : null,
              );
              widget.onMaxPriceChanged(
                _maxCtrl.text.isNotEmpty ? double.tryParse(_maxCtrl.text) : null,
              );
              widget.onSortChanged(_sortBy);
              widget.onApply();
            },
            child: const Text('Apply Filters', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
