import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/product_service.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/skeleton.dart';

class WishlistScreen extends ConsumerStatefulWidget {
  const WishlistScreen({super.key});

  @override
  ConsumerState<WishlistScreen> createState() => _WishlistScreenState();
}

class _WishlistScreenState extends ConsumerState<WishlistScreen> {
  List<Product> _wishlistedProducts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWishlist();
  }

  Future<void> _loadWishlist() async {
    setState(() => _isLoading = true);
    try {
      final ids = await ProductService.getFavoriteIds();
      if (ids.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final products = <Product>[];
      for (final id in ids) {
        try {
          products.add(await ProductService.getProduct(id));
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _wishlistedProducts = products;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProv = ref.watch(authProvider);

    if (authProv.user == null) {
      return Scaffold(
        backgroundColor: AppTheme.canvasWhite,
        extendBodyBehindAppBar: true,
        appBar: AppTheme.glassAppBar(context: context, title: const Text('Wishlist')),
        body: const Center(child: Text('Sign in to view your wishlist')),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.canvasWhite,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(context: context, title: const Text('Wishlist')),
      body: _isLoading
          ? Padding(
              padding: EdgeInsets.fromLTRB(12, MediaQuery.paddingOf(context).top + kToolbarHeight + 12, 12, 12),
              child: ProductGridSkeleton(),
            )
          : _wishlistedProducts.isEmpty
              ? _buildEmptyState()
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
                    itemCount: _wishlistedProducts.length,
                    itemBuilder: (context, index) {
                      final product = _wishlistedProducts[index];
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
                                        'GH\u00a2 ${product.price.toStringAsFixed(2)}',
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
