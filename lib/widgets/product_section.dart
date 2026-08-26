import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../config/app_theme.dart';
import '../models/product_model.dart';
import '../utils/responsive.dart';
import 'animated_press.dart';
import 'auto_scrolling_list.dart';
import 'discount_countdown.dart';
import 'instiy_logo_placeholder.dart';
import 'verification_badge.dart';

class ProductSection extends StatelessWidget {
  final String title;
  final IconData? titleIcon;
  final List<Product> products;
  final ValueChanged<Product> onTap;
  final ValueChanged<Product>? onAddToCart;
  final VoidCallback? onSeeAll;

  /// Per-product gate for the add-to-cart button. Products from another
  /// institution (cross-institution listings) hide their button when this
  /// returns false. Null keeps the button for every product.
  final bool Function(Product product)? canAddToCart;

  const ProductSection({
    super.key,
    required this.title,
    this.titleIcon,
    required this.products,
    required this.onTap,
    this.onAddToCart,
    this.onSeeAll,
    this.canAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: context.rw(16)),
          child: Row(
            children: [
              if (titleIcon != null) ...[
                Icon(titleIcon, size: context.ri(18), color: AppTheme.charcoalInk),
                SizedBox(width: context.rw(6)),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: context.rsp(18),
                  fontWeight: FontWeight.bold,
                  color: AppTheme.charcoalInk,
                ),
              ),
              const Spacer(),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Row(
                    children: [
                      Text(
                        'See All',
                        style: TextStyle(
                          fontSize: context.rsp(13),
                          fontWeight: FontWeight.w600,
                          color: AppTheme.accent,
                        ),
                      ),
                      SizedBox(width: context.rw(2)),
                      Icon(LucideIcons.chevronRight, size: context.ri(16), color: AppTheme.accent),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: context.rh(12)),
        AutoScrollingListView(
          height: context.rh(210),
          itemExtent: context.rw(163),
          padding: EdgeInsets.symmetric(horizontal: context.rw(12)),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return _HorizontalProductCard(
              product: product,
              onTap: () => onTap(product),
              onAddToCart: onAddToCart != null ? () => onAddToCart!(product) : null,
              showAddButton: canAddToCart?.call(product) ?? true,
            );
          },
        ),
      ],
    );
  }
}

class _HorizontalProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;
  final bool showAddButton;

  const _HorizontalProductCard({
    required this.product,
    required this.onTap,
    this.onAddToCart,
    this.showAddButton = true,
  });

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.isDiscountActive;

    return AnimatedPress(
      onTap: onTap,
      child: Container(
        width: context.rw(155),
        margin: EdgeInsets.symmetric(horizontal: context.rw(4)),
        decoration: BoxDecoration(
          color: AppTheme.pureSurface,
          borderRadius: BorderRadius.circular(context.rr(14)),
          border: Border.all(color: AppTheme.whisperBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
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
                      placeholder: (_, _) => const InstiyLogoPlaceholder(
                        width: double.infinity,
                        height: double.infinity,
                        animate: true,
                      ),
                      errorWidget: (_, _, _) => const InstiyLogoPlaceholder(
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    )
                  else
                    const InstiyLogoPlaceholder(
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  // Rating badge on thumbnail
                  if (product.averageRating != null && product.averageRating! > 0)
                    Positioned(
                      top: context.rh(6),
                      left: context.rw(6),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(5), vertical: context.rh(2)),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(context.rr(8)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.star, size: context.ri(9), color: const Color(0xFFFFD700)),
                            SizedBox(width: context.rw(2)),
                            Text(
                              product.averageRating!.toStringAsFixed(1),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.rsp(9),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (product.reviewCount != null && product.reviewCount! > 0) ...[
                              SizedBox(width: context.rw(1)),
                              Text(
                                '(${product.reviewCount})',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: context.rsp(8),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  if (hasDiscount)
                    Positioned(
                      top: context.rh(6),
                      right: context.rw(6),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: context.rw(6), vertical: context.rh(3)),
                        decoration: BoxDecoration(
                          color: AppTheme.destructive,
                          borderRadius: BorderRadius.circular(context.rr(10)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '-${product.discountPercent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: context.rsp(9),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (product.discountEndDate != null) ...[
                              SizedBox(height: context.rh(1)),
                              DiscountCountdown(
                                endDate: product.discountEndDate,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: context.rsp(7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  // Add to cart button
                  if (product.status == ProductStatus.available && showAddButton)
                    Positioned(
                      bottom: context.rh(6),
                      right: context.rw(6),
                      child: GestureDetector(
                        onTap: onAddToCart,
                        child: Container(
                          padding: EdgeInsets.all(context.rw(6)),
                          decoration: BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            LucideIcons.plus,
                            size: context.ri(14),
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Expanded(
              flex: 2,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: context.rw(10), vertical: context.rh(6)),
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
                    SizedBox(height: context.rh(2)),
                    if (hasDiscount) ...[
                      Text(
                        'GH\u00a2 ${product.effectivePrice.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: context.rsp(13),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.destructive,
                        ),
                      ),
                      Text(
                        'GH\u00a2 ${product.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: context.rsp(10),
                          color: AppTheme.mutedSteel,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    ] else
                      Text(
                        'GH\u00a2 ${product.price.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: context.rsp(13),
                          fontWeight: FontWeight.bold,
                          color: AppTheme.charcoalInk,
                        ),
                      ),
                    const Spacer(),
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
                                  VerificationBadge(size: context.ri(9)),
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
}
