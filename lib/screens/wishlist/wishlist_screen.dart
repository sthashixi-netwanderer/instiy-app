import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/product_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';

class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  final Map<String, Product> _productCache = {};
  bool _isLoading = true;
  ProviderSubscription< List<String> >? _favoritesSub;

  @override
  void initState() {
    super.initState();
    _favoritesSub = ref.listenManual(
      productProvider.select((p) => p.favoriteIds),
      (previous, next) => _syncWithFavorites(next),
    );
    _loadWishlist();
  }

  @override
  void dispose() {
    _favoritesSub?.close();
    super.dispose();
  }

  Future<void> _loadWishlist() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(productProvider).loadFavoriteIds();
      final ids = List<String>.from(ref.read(productProvider).favoriteIds);
      _productCache.clear();
      for (final id in ids) {
        try {
          _productCache[id] = await ProductService.getProduct(id);
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  /// Reacts to favorite toggles made anywhere in the app (e.g. product
  /// detail) without needing to re-open this screen.
  Future<void> _syncWithFavorites(List<String> ids) async {
    final knownIds = ids.toSet();
    _productCache.removeWhere((id, _) => !knownIds.contains(id));
    final missing = ids.where((id) => !_productCache.containsKey(id)).toList();
    for (final id in missing) {
      try {
        _productCache[id] = await ProductService.getProduct(id);
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.cleanBackground,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Wishlist')),
        body: const Center(child: Text('Sign in to view your wishlist')),
      );
    }

    final favoriteIds = ref.watch(productProvider.select((p) => p.favoriteIds));
    final wishlistedProducts = favoriteIds
        .map((id) => _productCache[id])
        .whereType<Product>()
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Wishlist')),
      body: _isLoading
          ? Padding(
              padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + kToolbarHeight + 12, 12, 12),
              child: ProductGridSkeleton(),
            )
          : wishlistedProducts.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadWishlist,
                  child: ListView(
                    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight + 12),
                    children: [_buildEmptyState()],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadWishlist,
                  child: GridView.builder(
                    padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + kToolbarHeight + 12, 12, 12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: wishlistedProducts.length,
                    itemBuilder: (context, index) {
                      final product = wishlistedProducts[index];
                      return GestureDetector(
                        onTap: () => Navigator.of(context).pushNamed(
                          '/product',
                          arguments: product.id,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppTheme.pureSurface,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: AppTheme.whisperBorder),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: product.effectiveThumbnail != null
                                    ? CachedNetworkImage(
                                        imageUrl: product.effectiveThumbnail!,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        memCacheWidth: 160,
                                        placeholder: (_, _) =>
                                            Container(color: AppTheme.warmMist),
                                        errorWidget: (_, _, _) =>
                                            Container(color: AppTheme.warmMist),
                                      )
                                    : Container(
                                        color: AppTheme.warmMist,
                                        child: const Icon(LucideIcons.image),
                                      ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        formatGhs(product.price),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.charcoalInk,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return EmptyState(
      icon: LucideIcons.heart,
      title: 'Your wishlist is empty',
      description: 'Save items you love by tapping the heart icon.',
      actionLabel: 'Explore Products',
      onActionPressed: () => Navigator.of(context).pushNamed('/explore'),
    );
  }
}
