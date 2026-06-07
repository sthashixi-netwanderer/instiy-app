---
name: add-action-button-to-product-cards
description: Adding interactive action buttons (cart, wishlist, etc.) to product card thumbnails across all screens
source: auto-skill
extracted_at: '2026-05-31T16:36:34.371Z'
---

# Adding Action Buttons to Product Card Thumbnails

When you need to add tappable action buttons (e.g., add to cart, wishlist toggle) as overlays on product card thumbnails across all screen locations.

## Find All Card Locations

Product cards exist in **3 separate locations** — each must be updated independently:

1. `lib/widgets/product_card.dart` — Main reusable `ProductCard` widget (grid views, seller profile)
2. `lib/widgets/product_section.dart` — `_HorizontalProductCard` (home screen horizontal scrolls)
3. `lib/screens/explore/explore_screen.dart` — `_buildProductCard()` inline method (explore grid)

Search pattern: `grep_search` for `ProductCard\(` and `_buildProductCard` and `_HorizontalProductCard`

## Steps

### 1. Understand the Provider API

Check the provider for the action method signature:
```dart
// e.g., in cart_provider.dart
Future<void> addToCart({
  required String productId,
  required String title,
  required double price,
  String? thumbnail,
  String? sellerId,
  String? sellerName,
  int quantity = 1,
  double deliveryFee = 0.0,
}) async { ... }
```

### 2. Add Button to the Thumbnail Stack

Add a `Positioned` widget inside the existing `Stack` on the thumbnail. Place it **last** in the children list so it renders on top:

```dart
// Bottom-right of thumbnail
if (!inCart && product.status == ProductStatus.available)
  Positioned(
    bottom: 8,
    right: 8,
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
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: AppTheme.accent,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          LucideIcons.plus,
          size: 18,
          color: Colors.white,
        ),
      ),
    ),
  ),
```

### 3. Adjust Per Card Variant

| Card Type | Icon Size | Padding | Condition Logic |
|-----------|-----------|---------|-----------------|
| `ProductCard` (grid) | 18px | `all(8)` | `!inCart && product.status == ProductStatus.available` |
| `_HorizontalProductCard` | 14px | `all(6)` | `product.status == ProductStatus.available` (no cart check — onTap navigates) |
| Explore `_buildProductCard` | 18px | `all(8)` | `!inCart && product.status == ProductStatus.available && !isOwnProduct` |

### 4. Handle Access to Providers

- **`ConsumerStatefulWidget`** (ProductCard): Use `ref.read(cartProvider)` directly
- **`StatelessWidget`** (_HorizontalProductCard): Cannot access ref — use the existing `onTap` callback instead (navigates to detail where user can add to cart)
- **`ConsumerStatefulWidget`** (explore screen): Use `ref.read(cartProvider)` directly

### 5. Verify All Badge Positions Don't Overlap

Check existing `Positioned` badges on the thumbnail:
- **Top-left**: "In Cart" badge, rating badge
- **Top-right**: Discount badge, wishlist heart
- **Bottom-left**: Video play icon
- **Bottom-right**: ← Action button goes here

If the bottom-right is occupied, offset accordingly.

## Key Principles

- **Conditional visibility**: Hide button when action is already done (e.g., item already in cart)
- **Respect product status**: Don't show on sold/reserved items
- **Own products**: In explore/home, hide for own listings (`!isOwnProduct`)
- **Use `AppTheme.accent`** for the button background
- **Circular shape**: `BoxDecoration(shape: BoxShape.circle)`
- **Big enough to tap**: Minimum 8px padding with 18px icon (34px touch target)
