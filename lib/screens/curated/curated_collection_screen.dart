import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../config/app_theme.dart';
import '../../models/curated_collection_model.dart';
import '../../models/product_model.dart';
import '../../providers/providers.dart';
import '../../services/curated_collection_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/adaptive_nav.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/responsive_layout.dart';
import '../../providers/block_provider.dart';
import 'package:instiy/utils/formatters.dart';

class CuratedCollectionScreen extends ConsumerStatefulWidget {
  final String collectionId;

  const CuratedCollectionScreen({
    super.key,
    required this.collectionId,
  });

  @override
  ConsumerState<CuratedCollectionScreen> createState() => _CuratedCollectionScreenState();
}

class _CuratedCollectionScreenState extends ConsumerState<CuratedCollectionScreen> {
  CuratedCollection? _collection;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCollection();
    });
  }

  Future<void> _loadCollection() async {
    try {
      final allSections = await CuratedCollectionService.getHomeSections();
      final blockProv = BlockProvider.instance;
      final filteredSections = allSections.map((s) {
        final filteredItems = s.items.where((item) {
          if (item.product != null) {
            return !blockProv.isUserBlocked(item.product!.sellerId);
          }
          return true;
        }).toList();
        return CuratedCollection(
          id: s.id, title: s.title,
          subtitle: s.subtitle, icon: s.icon, imageUrl: s.imageUrl,
          displayMode: s.displayMode, contentType: s.contentType,
          maxItems: s.maxItems, sortOrder: s.sortOrder,
          isVisible: s.isVisible, items: filteredItems,
        );
      }).toList();
      final collection = filteredSections.firstWhere(
        (c) => c.id == widget.collectionId,
        orElse: () => throw Exception('Collection not found'),
      );
      if (mounted) {
        setState(() {
          _collection = collection;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final products = _collection?.items.where((item) => item.product != null).map((item) => item.product!).toList() ?? [];

    return ResponsiveLayout(
      type: ResponsiveLayoutType.general,
      backgroundColor: AppTheme.cleanBackground,
      bottomNavigationBar: const AdaptiveNav(currentIndex: 0),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(context),
            if (_isLoading)
              _buildLoadingSliver()
            else if (_error != null)
              _buildErrorSliver(context)
            else if (_collection == null)
              _buildNotFoundSliver(context)
            else
              _buildContentSliver(context, products),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: context.rh(200),
      pinned: true,
      backgroundColor: AppTheme.headerBarSolid,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppTheme.charcoalInk),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(
        _collection?.title ?? 'Collection',
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppTheme.charcoalInk,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: _collection?.imageUrl != null
            ? Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(_collection!.imageUrl!),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.3),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  padding: EdgeInsets.only(
                    left: context.rw(16),
                    right: context.rw(16),
                    bottom: context.rh(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (_collection?.subtitle != null)
                        Text(
                          _collection!.subtitle!,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white70,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        '${_collection?.items.where((item) => item.product != null).length ?? 0} products',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Container(
                color: AppTheme.accent.withValues(alpha: 0.1),
                padding: EdgeInsets.only(
                  left: context.rw(16),
                  right: context.rw(16),
                  bottom: context.rh(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_collection?.subtitle != null)
                      Text(
                        _collection!.subtitle!,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.charcoalInk,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${_collection?.items.where((item) => item.product != null).length ?? 0} products',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildLoadingSliver() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
        child: Column(
          children: List.generate(
            3,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: context.rh(16)),
              child: _buildProductCardSkeleton(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(16)),
        child: EmptyState(
          icon: Icons.error_outline,
          title: 'Failed to load collection',
          description: _error ?? 'Please try again later',
          actionLabel: 'Retry',
          onActionPressed: () => _loadCollection(),
        ),
      ),
    );
  }

  Widget _buildNotFoundSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(16)),
        child: EmptyState(
          icon: Icons.inventory_2_outlined,
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
          padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(16)),
          child: EmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'No products yet',
            description: 'This collection has no products yet',
            actionLabel: 'Go Back',
            onActionPressed: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: context.rw(16), vertical: context.rh(16)),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return _buildProductCard(products[index]);
          },
          childCount: products.length,
        ),
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
                fit: StackFit.expand,
                children: [
                  if (product.effectiveThumbnail != null)
                    CachedNetworkImage(
                      imageUrl: product.effectiveThumbnail!,
                      fit: BoxFit.cover,
                      memCacheWidth: 160,
                      placeholder: (_, _) => Container(color: AppTheme.warmMist),
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.warmMist,
                        child: Icon(Icons.image, color: AppTheme.mutedSteel, size: context.ri(24)),
                      ),
                    )
                  else
                    Container(
                      color: AppTheme.warmMist,
                      child: Icon(Icons.image, color: AppTheme.mutedSteel, size: context.ri(24)),
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
                            Icon(Icons.shopping_cart, size: context.ri(10), color: Colors.white),
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
                          ],
                        ),
                      ),
                    ),
                  if (hasDiscount)
                    Positioned(
                      top: context.rh(8),
                      right: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
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
                  if (product.status == ProductStatus.available && !inCart)
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

  Widget _buildProductCardSkeleton() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(context.rr(16)),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: context.rh(180),
            color: AppTheme.warmMist,
          ),
          Padding(
            padding: EdgeInsets.all(context.rw(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: context.rw(120),
                  height: context.rh(12),
                  color: AppTheme.warmMist,
                ),
                SizedBox(height: context.rh(8)),
                Container(
                  width: context.rw(80),
                  height: context.rh(12),
                  color: AppTheme.warmMist,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
