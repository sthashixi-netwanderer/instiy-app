import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../providers/providers.dart';
import '../utils/responsive.dart';
import 'animated_press.dart';
import 'discount_countdown.dart';
import 'verification_badge.dart';
import 'package:instiy/utils/formatters.dart';

class ProductCard extends ConsumerStatefulWidget {
  final Product product;
  final VoidCallback onTap;
  final bool showSeller;
  final int? viewCount;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.showSeller = true,
    this.viewCount,
  });

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard> {
  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final inCart = cartState.isInCart(widget.product.id);
    final product = widget.product;
    final hasDiscount = product.isDiscountActive;

    final authState = ref.watch(authProvider);
    final isOwner = authState.user?.id == product.sellerId;
    bool needsPermission = false;
    if (authState.isAuthenticated) {
      final userUni = authState.user?.university;
      if (userUni != null && userUni.trim().isNotEmpty && product.campuses.isNotEmpty) {
        final matches = product.campuses.any((c) =>
            c.toLowerCase().trim() == userUni.toLowerCase().trim());
        needsPermission = !matches;
      }
    }

    return AnimatedPress(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.55),
              AppTheme.glassSurfaceLight,
            ],
          ),
          borderRadius: BorderRadius.circular(context.rr(20)),
          border: Border.all(
            color: inCart ? AppTheme.accent : AppTheme.glassBorder,
            width: inCart ? 1.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: inCart
                  ? AppTheme.accent.withValues(alpha: 0.25)
                  : const Color(0x1F4C1D95),
              blurRadius: inCart ? 20 : 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  if (product.effectiveThumbnail != null)
                    CachedNetworkImage(
                      imageUrl: product.effectiveThumbnail!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      memCacheWidth: 160,
                      placeholder: (_, _) =>
                          Container(color: AppTheme.warmMist),
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
                  if (hasDiscount)
                    Positioned(
                      top: context.rh(8),
                      right: context.rw(8),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(8), vertical: context.rh(4)),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFF43F5E), AppTheme.destructive],
                          ),
                          borderRadius: BorderRadius.circular(context.rr(12)),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.destructive.withValues(alpha: 0.4),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '-${formatCurrency(product.discountPercent)}%',
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
                  // Add to cart button
                  if (!inCart && product.status == ProductStatus.available && !needsPermission && !isOwner)
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
                          padding: EdgeInsets.all(context.rw(9)),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppTheme.accentBright, AppTheme.accent],
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.accent.withValues(alpha: 0.5),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
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
            Padding(
              padding: EdgeInsets.fromLTRB(context.rw(10), context.rh(8), context.rw(10), context.rh(10)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (product.title.isNotEmpty)
                    Text(
                      product.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: context.rsp(13),
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoalInk,
                      ),
                    ),
                  SizedBox(height: context.rh(6)),
                    // Price + total views
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: hasDiscount
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      formatGhs(product.effectivePrice),
                                      style: TextStyle(
                                        fontSize: context.rsp(16),
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.destructive,
                                      ),
                                    ),
                                    Text(
                                      formatGhs(product.effectivePrice),
                                      style: TextStyle(
                                        fontSize: context.rsp(12),
                                        color: AppTheme.mutedSteel,
                                        decoration: TextDecoration.lineThrough,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  formatGhs(product.effectivePrice),
                                  style: TextStyle(
                                    fontSize: context.rsp(16),
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.charcoalInk,
                                  ),
                                ),
                        ),
                        if ((widget.viewCount ?? 0) > 0) ...[
                          Icon(LucideIcons.eye, size: context.ri(11), color: AppTheme.mutedSteel),
                          SizedBox(width: context.rw(3)),
                          Text(
                            '${widget.viewCount}',
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
                    if (widget.showSeller && product.sellerName != null)
                      Row(
                        children: [
                          ShadAvatar(
                            product.sellerAvatar?.isNotEmpty == true ? product.sellerAvatar : null,
                            size: Size(context.ri(18), context.ri(18)),
                            backgroundColor: AppTheme.accent,
                            placeholder: Text(
                              (product.businessName ?? product.sellerName ?? 'S')[0].toUpperCase(),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: context.rsp(8),
                              ),
                            ),
                          ),
                          SizedBox(width: context.rw(4)),
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    product.businessName ?? product.sellerName!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: context.rsp(10),
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
          ],
        ),
      ),
    );
  }
}
