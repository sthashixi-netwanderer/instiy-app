---
name: merge-badges-into-product-cards
description: Merging multiple overlay badges (discount %, countdown, etc.) into a single cohesive badge on product card thumbnails across all screens
source: auto-skill
extracted_at: '2026-05-31T18:28:05.307Z'
---

# Merging Badges into Product Cards

When you need to combine multiple separate overlay elements (e.g., discount percentage + countdown timer) into a single cohesive badge on product card thumbnails across all screen locations.

## Context

Product cards exist in **5+ separate implementations** — each must be updated independently:

| Location | Widget | Notes |
|----------|--------|-------|
| `lib/widgets/product_card.dart` | `ProductCard` | Main reusable grid card (ConsumerStatefulWidget) |
| `lib/widgets/product_section.dart` | `_HorizontalProductCard` | Horizontal scroll cards on home screen |
| `lib/screens/explore/explore_screen.dart` | `_buildProductCard()` | Inline method in explore screen |
| `lib/widgets/home_carousel.dart` | Carousel slides | Has its own badge implementation |
| `lib/widgets/featured_carousel.dart` | Featured carousel | May be missing the secondary element entirely |
| `lib/screens/product/product_detail_screen.dart` | Detail screen | Larger layout — can keep its own styled container |

Search pattern: `grep_search` for the badge widget name (e.g., `DiscountCountdown`) and the percentage text pattern (e.g., `discountPercent`) across `lib/`.

## Procedure

### Step 1: Research UX patterns (optional but recommended)

Use `creep search` to find best practices before choosing a layout:

```bash
creep search "discount badge countdown timer product card mobile UX" -n 5
```

Key findings from research:
- **Badges outperform bars on mobile** — compact, in the natural eye-path
- **Single cohesive badge** creates stronger urgency association than separate elements
- **Red for urgency** — use the destructive/error color for time-sensitive badges
- **Position**: top-right of thumbnail is the standard for sale/discount badges

### Step 2: Make the shared widget configurable

If a reusable widget already exists (e.g., `DiscountCountdown`), add a `style` parameter so it can be embedded inside badges with custom text sizing:

```dart
class DiscountCountdown extends StatefulWidget {
  final DateTime? endDate;
  final TextStyle? style;  // NEW — allows embedding in badges

  const DiscountCountdown({super.key, this.endDate, this.style});
```

Use the style in the build method with a fallback:
```dart
Text(_label, style: widget.style ?? const TextStyle(
  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500,
));
```

### Step 3: Merge into a single badge container

Replace the two separate elements (badge + separate countdown) with a single `Container` that has a `Column` inside:

```dart
// BEFORE: Two separate Positioned widgets in a Column
Positioned(
  top: 8, right: 8,
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Container(/* badge only */),
      SizedBox(height: 3),
      Container(/* countdown in separate container */),
    ],
  ),
),

// AFTER: Single badge with integrated content
Positioned(
  top: 8, right: 8,
  child: Container(
    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: AppTheme.destructive,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('-${product.discountPercent.toStringAsFixed(0)}%',
          style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
        if (product.discountEndDate != null) ...[
          SizedBox(height: 1),
          DiscountCountdown(
            endDate: product.discountEndDate,
            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    ),
  ),
),
```

### Step 4: Remove the old separate element from the info area

If the secondary element (e.g., countdown) was previously shown below the price in the card's info area, remove it:

```dart
// REMOVE this block from the info area:
if (hasDiscount && _secondsRemaining != null && _secondsRemaining! > 0) ...[
  SizedBox(height: 1),
  Row(children: [
    Icon(LucideIcons.clock, size: 10, color: AppTheme.destructive),
    SizedBox(width: 3),
    Text(_formatCountdown(_secondsRemaining!), ...),
  ]),
],
```

Also remove the associated `Timer?` state, `initState`/`didUpdateWidget` timer logic, `dispose` cleanup, and `_formatCountdown` method if they're no longer needed. Remove `import 'dart:async'` if no other async code remains.

### Step 5: Update all card locations

For each card implementation found in Step 1:

1. **If it had a separate secondary element below the badge** → merge into the badge (Step 3)
2. **If it only had the primary badge** → add the secondary element inside the badge
3. **If it had a private duplicate widget** (e.g., home carousel's `_DiscountCountdown`) → replace with the shared widget and delete the private class

### Step 6: Handle responsive sizing per card variant

| Card Type | Badge Font | Countdown Font | Padding |
|-----------|-----------|----------------|---------|
| `ProductCard` (grid) | `rsp(10)` | `rsp(8)` | `rw(8), rh(4)` |
| `_HorizontalProductCard` | `rsp(9)` | `rsp(7)` | `rw(6), rh(3)` |
| Explore `_buildProductCard` | `rsp(10)` | `rsp(8)` | `rw(8), rh(4)` |
| Home carousel | `12` fixed | `10` fixed | `horizontal(10), vertical(5)` |
| Featured carousel | `12` fixed | `10` fixed | `horizontal(10), vertical(5)` |

### Step 7: Verify

```bash
flutter analyze lib/widgets/discount_countdown.dart lib/widgets/product_card.dart \
  lib/screens/explore/explore_screen.dart lib/widgets/product_section.dart \
  lib/widgets/home_carousel.dart lib/widgets/featured_carousel.dart
```

## Key Principles

- **One badge, one container** — avoid stacking separate `Container` widgets in a `Column` for related info
- **Use `mainAxisSize: MainAxisSize.min`** on the inner Column so the badge shrinks to content
- **`SizedBox(height: 1)`** between lines — tight spacing inside badges
- **Same background color** for both lines (don't use black54 for countdown + red for percentage)
- **Smaller font for secondary info** — countdown is 2px smaller than the percentage text
- **Detail screens can differ** — product detail screen has more space and can keep its own styled container below the price
- **Remove dead code** — delete private duplicate widgets, unused Timer state, unused imports
- **Carousel cards use fixed sizes** (not responsive helpers) since they don't use the Responsive extension
