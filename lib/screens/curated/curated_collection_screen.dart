import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../config/app_theme.dart';
import '../../models/curated_collection_model.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../utils/purchase_access.dart';
import '../../utils/responsive.dart';
import '../../widgets/adaptive_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/responsive_layout.dart';
import '../../widgets/skeleton.dart';
import 'package:instiy/utils/formatters.dart';

class CuratedCollectionScreen extends ConsumerStatefulWidget {
  final String collectionId;

  const CuratedCollectionScreen({super.key, required this.collectionId});

  @override
  ConsumerState<CuratedCollectionScreen> createState() =>
      _CuratedCollectionScreenState();
}

class _CuratedCollectionScreenState
    extends ConsumerState<CuratedCollectionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prov = ref.read(curatedProvider);
      prov.ensureInitialized();
      if (prov.sections.isEmpty) {
        prov.loadSections();
      }
    });
  }

  Future<void> _loadCollection() async {
    await ref.read(curatedProvider).loadSections();
  }

  @override
  Widget build(BuildContext context) {
    final curatedProv = ref.watch(curatedProvider);
    final sections = curatedProv.sections;
    CuratedCollection? collection;
    for (final s in sections) {
      if (s.id == widget.collectionId) {
        collection = s;
        break;
      }
    }
    final isLoading = curatedProv.isLoading;
    final error = curatedProv.error;
    final products =
        collection?.items
            .where((item) => item.product != null)
            .map((item) => item.product!)
            .toList() ??
        [];

    final collectionImage = collection?.imageUrl;
    final hasImage =
        collectionImage != null && collectionImage.trim().isNotEmpty;
    final collectionSubtitle = collection?.subtitle;
    final hasSubtitle =
        collectionSubtitle != null && collectionSubtitle.trim().isNotEmpty;
    // The glass app bar paints its own status-bar padding and is laid out by
    // the ResponsiveLayout scaffold with extendBodyBehindAppBar, so the body
    // only needs to clear the bar itself plus a small gap.
    final topPadding =
        MediaQuery.paddingOf(context).top + kToolbarHeight + context.rh(12);

    return ResponsiveLayout(
      type: ResponsiveLayoutType.general,
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: Text(
          collection?.title ?? 'Collection',
          style: TextStyle(
            fontSize: context.rsp(16),
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoalInk,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (products.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(right: context.rw(12)),
              child: Center(
                child: Text(
                  '${products.length} ${products.length == 1 ? 'product' : 'products'}',
                  style: TextStyle(
                    color: AppTheme.mutedSteel,
                    fontSize: context.rsp(13),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: const AdaptiveNav(currentIndex: 0),
      child: RefreshIndicator(
        onRefresh: _loadCollection,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: topPadding)),
            if (hasImage)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.rw(16),
                    0,
                    context.rw(16),
                    context.rh(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(context.rr(16)),
                    child: Stack(
                      children: [
                        CachedNetworkImage(
                          imageUrl: collectionImage,
                          width: double.infinity,
                          height: context.rh(140),
                          fit: BoxFit.cover,
                        ),
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (hasSubtitle)
                          Positioned(
                            left: context.rw(14),
                            right: context.rw(14),
                            bottom: context.rh(12),
                            child: Text(
                              collectionSubtitle,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.rsp(13),
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            else if (hasSubtitle)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    context.rw(16),
                    0,
                    context.rw(16),
                    context.rh(8),
                  ),
                  child: Text(
                    collectionSubtitle,
                    style: TextStyle(
                      fontSize: context.rsp(13),
                      color: AppTheme.mutedSteel,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (isLoading && collection == null)
              _buildLoadingSliver()
            else if (error != null && collection == null)
              _buildErrorSliver(context)
            else if (collection == null)
              _buildNotFoundSliver(context)
            else
              _buildContentSliver(context, products),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingSliver() {
    return SliverPadding(
      padding: EdgeInsets.symmetric(
        horizontal: context.rw(16),
        vertical: context.rh(4),
      ),
      sliver: const SliverToBoxAdapter(child: ProductGridSkeleton(count: 6)),
    );
  }

  Widget _buildErrorSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.rw(16),
          vertical: context.rh(32),
        ),
        child: EmptyState(
          icon: LucideIcons.alertCircle,
          title: 'Failed to load collection',
          description:
              ref.watch(curatedProvider).error ?? 'Please try again later',
          actionLabel: 'Retry',
          onActionPressed: () => _loadCollection(),
        ),
      ),
    );
  }

  Widget _buildNotFoundSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.rw(16),
          vertical: context.rh(32),
        ),
        child: EmptyState(
          icon: LucideIcons.packageSearch,
          title: 'Collection not found',
          description: 'The collection you are looking for does not exist',
          actionLabel: 'Go Back',
          onActionPressed: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }

  Widget _buildContentSliver(BuildContext context, List<Product> products) {
    if (products.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.rw(16),
            vertical: context.rh(32),
          ),
          child: EmptyState(
            icon: LucideIcons.shoppingBag,
            title: 'No products yet',
            description: 'This collection has no products yet',
            actionLabel: 'Go Back',
            onActionPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        context.rw(16),
        context.rh(4),
        context.rw(16),
        context.rh(24),
      ),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          return _buildProductCard(products[index]);
        }, childCount: products.length),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: context.isDesktop ? 4 : (context.isTablet ? 3 : 2),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.72,
        ),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final cart = ref.watch(cartProvider);
    final inCart = cart.isInCart(product.id);
    final hasDiscount = product.isDiscountActive;

    return GestureDetector(
      onTap: () =>
          Navigator.of(context).pushNamed('/product', arguments: product.id),
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
                fit: StackFit.expand,
                children: [
                  if (product.effectiveThumbnail != null)
                    CachedNetworkImage(
                      imageUrl: product.effectiveThumbnail!,
                      fit: BoxFit.cover,
                      memCacheWidth: 160,
                      placeholder: (_, _) =>
                          Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.warmMist,
                        child: Icon(
                          Icons.image,
                          color: AppTheme.mutedSteel,
                          size: context.ri(24),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: AppTheme.warmMist,
                      child: Icon(
                        Icons.image,
                        color: AppTheme.mutedSteel,
                        size: context.ri(24),
                      ),
                    ),
                  if (inCart)
                    Positioned(
                      top: context.rh(8),
                      left: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(8),
                          vertical: context.rh(4),
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(context.rr(12)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shopping_cart,
                              size: context.ri(10),
                              color: Colors.white,
                            ),
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
                  if (product.averageRating != null &&
                      product.averageRating! > 0)
                    Positioned(
                      top: context.rh(inCart ? 36 : 8),
                      left: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(6),
                          vertical: context.rh(3),
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(context.rr(10)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: context.ri(10),
                              color: const Color(0xFFFFD700),
                            ),
                            SizedBox(width: context.rw(3)),
                            Text(
                              product.averageRating!.toStringAsFixed(1),
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
                  if (hasDiscount)
                    Positioned(
                      top: context.rh(8),
                      right: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(8),
                          vertical: context.rh(4),
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.destructive,
                          borderRadius: BorderRadius.circular(context.rr(12)),
                        ),
                        child: Text(
                          '-${formatCurrency(product.discountPercent)}%',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: context.rsp(10),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  if (product.status != ProductStatus.available)
                    Positioned(
                      top: context.rh(8),
                      right: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.rw(8),
                          vertical: context.rh(4),
                        ),
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
                  if (product.status == ProductStatus.available &&
                      !inCart &&
                      // Cross-institution listings the buyer has no access
                      // to can't be added from curated collections.
                      !PurchaseAccess.isRestrictedForBuyer(
                        campuses: product.campuses,
                        userUniversity: ref.read(authProvider).user?.university,
                      ))
                    Positioned(
                      bottom: context.rh(8),
                      right: context.rw(8),
                      child: GestureDetector(
                        onTap: () {
                          ref
                              .read(cartProvider)
                              .addToCart(
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
                          decoration: const BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.add,
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
                padding: EdgeInsets.symmetric(
                  horizontal: context.rw(6),
                  vertical: context.rh(4),
                ),
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
                    if (hasDiscount)
                      Column(
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
                            formatGhs(product.effectivePrice),
                            style: TextStyle(
                              fontSize: context.rsp(10),
                              color: AppTheme.mutedSteel,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        formatGhs(product.effectivePrice),
                        style: TextStyle(
                          fontSize: context.rsp(14),
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
  }
}
