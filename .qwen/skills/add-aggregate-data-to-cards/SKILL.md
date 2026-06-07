---
name: add-aggregate-data-to-cards
description: Adding aggregate related data (ratings, counts, etc.) from a related Supabase table to list items/cards in Flutter
source: auto-skill
extracted_at: '2026-05-31T16:26:58.238Z'
---

# Adding Aggregate Data to Cards/List Items

When you need to show aggregated data from a related table (e.g., average rating, review count, comment count) on product cards or list items across multiple screens.

## Steps

### 1. Add Nullable Fields to the Model

```dart
// In the model class (e.g., Product)
final double? averageRating;
final int? reviewCount;
```

Add to constructor with defaults, and parse from JSON:
```dart
averageRating: (json['average_rating'] as num?)?.toDouble(),
reviewCount: (json['review_count'] as num?)?.toInt(),
```

### 2. Add `copyWith` Method to the Model

Required for immutable updates after fetching aggregates:

```dart
Model copyWith({double? averageRating, int? reviewCount}) {
  return Model(
    // ... all existing fields ...
    averageRating: averageRating ?? this.averageRating,
    reviewCount: reviewCount ?? this.reviewCount,
  );
}
```

### 3. Batch-Fetch Aggregates in the Service

After the main query, fetch aggregates for all items in one query:

```dart
// In ProductService.getProducts()
final products = /* parse main query */;

if (products.isNotEmpty) {
  final productIds = products.map((p) => p.id).toList();
  final reviewsResponse = await SupabaseService.table('product_reviews')
      .select('product_id, rating')
      .inFilter('product_id', productIds)
      .not('rating', 'is', null);

  // Group by product_id
  final Map<String, List<num>> ratingsByProduct = {};
  for (final review in reviewsResponse as List) {
    final productId = review['product_id'] as String;
    final rating = review['rating'] as num?;
    if (rating != null) {
      ratingsByProduct.putIfAbsent(productId, () => []).add(rating);
    }
  }

  // Map back to products using copyWith
  return products.map((product) {
    final ratings = ratingsByProduct[product.id];
    if (ratings != null && ratings.isNotEmpty) {
      final avg = ratings.reduce((a, b) => a + b) / ratings.length;
      return product.copyWith(averageRating: avg, reviewCount: ratings.length);
    }
    return product.copyWith(averageRating: 0, reviewCount: 0);
  }).toList();
}
```

### 4. Add Overlay Badge to All UI Locations

**Find all card implementations** — search for the widget name across the codebase. Common locations:
- Main reusable widget (e.g., `widgets/product_card.dart`)
- Horizontal scroll cards (e.g., `widgets/product_section.dart`)
- Screen-specific inline cards (e.g., `screens/explore/explore_screen.dart`)

**Add badge to the Stack** (positioned on thumbnail):

```dart
if (item.averageRating != null && item.averageRating! > 0)
  Positioned(
    top: 8,
    left: 8,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.star, size: 10, color: Color(0xFFFFD700)),
          const SizedBox(width: 3),
          Text(
            item.averageRating!.toStringAsFixed(1),
            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
          ),
          if (item.reviewCount != null && item.reviewCount! > 0) ...[
            const SizedBox(width: 2),
            Text(
              '(${item.reviewCount})',
              style: const TextStyle(color: Colors.white70, fontSize: 9),
            ),
          ],
        ],
      ),
    ),
  ),
```

**Handle stacking with other badges** — if "In Cart" or similar badges exist on top-left, offset the rating badge:
```dart
top: inCart ? 36 : 8,  // Push down if "In Cart" badge is showing
```

## Removing Seller Info from Cards

When replacing seller info with aggregate data, remove the seller row from **all 3 card locations**:

1. Find the `if (widget.showSeller)` / seller `Row` block with `ShadAvatar`, seller name, `VerificationBadge`
2. Replace with just the condition badge or remove entirely
3. Remove unused imports: `verification_badge.dart`, and `ShadAvatar` from `shadcn_ui` if no longer used
4. The `showSeller` constructor parameter can remain for backward compatibility (seller profile still passes `false`)

## Key Principles

- **One batch query** for aggregates — don't N+1 query per item
- **Use `copyWith`** for immutable model updates
- **Update ALL card locations** — search for the widget class name to find every usage
- **Use `Colors.black54`** background for overlay badges on thumbnails for readability
- **Gold star color**: `Color(0xFFFFD700)`
- **Clean up unused imports** after removing UI elements
