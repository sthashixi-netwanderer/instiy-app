import 'product_model.dart';
import 'category_model.dart';

class CuratedCollection {
  final String id;
  final String title;
  final String? subtitle;
  final String? icon;
  final String? imageUrl;
  final String displayMode; // 'horizontal' | 'grid'
  final String contentType; // 'products' | 'categories'
  final int maxItems;
  final bool isVisible;
  final int sortOrder;
  final List<CuratedItem> items;

  CuratedCollection({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.imageUrl,
    this.displayMode = 'horizontal',
    this.contentType = 'products',
    this.maxItems = 10,
    this.isVisible = true,
    this.sortOrder = 0,
    this.items = const [],
  });

  factory CuratedCollection.fromRpcRow(Map<String, dynamic> json) {
    return CuratedCollection(
      id: json['collection_id'] as String,
      title: json['collection_title'] as String,
      subtitle: json['collection_subtitle'] as String?,
      icon: json['collection_icon'] as String?,
      imageUrl: json['collection_image_url'] as String?,
      displayMode: json['collection_display_mode'] as String? ?? 'horizontal',
      contentType: json['collection_content_type'] as String? ?? 'products',
      maxItems: (json['collection_max_items'] as num?)?.toInt() ?? 10,
      isVisible: true, // RPC only returns visible
      sortOrder: (json['collection_sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  /// Parse RPC response rows into a list of CuratedCollections with their items
  static List<CuratedCollection> parseRpcResponse(List<dynamic> rows) {
    final Map<String, CuratedCollection> collectionsMap = {};
    final Map<String, List<CuratedItem>> itemsMap = {};

    for (final row in rows) {
      final json = row as Map<String, dynamic>;
      final collectionId = json['collection_id'] as String;

      if (!collectionsMap.containsKey(collectionId)) {
        collectionsMap[collectionId] = CuratedCollection.fromRpcRow(json);
        itemsMap[collectionId] = [];
      }

      final itemId = json['item_id'] as String?;
      if (itemId != null) {
        Product? product;
        Category? category;

        if (json['item_product_id'] != null) {
          product = Product(
            id: json['item_product_id'] as String,
            sellerId: json['product_seller_id'] as String? ?? '',
            title: json['product_title'] as String? ?? '',
            description: '',
            price: (json['product_price'] as num?)?.toDouble() ?? 0,
            imageUrls: (json['product_image_urls'] as List<dynamic>?)
                    ?.map((e) => e as String)
                    .toList() ??
                [],
            thumbnailUrl: json['product_thumbnail'] as String?,
            condition: ProductCondition.values.firstWhere(
              (e) => e.name == (json['product_condition'] as String? ?? 'used'),
              orElse: () => ProductCondition.used,
            ),
            status: ProductStatus.values.firstWhere(
              (e) => e.name == (json['product_status'] as String? ?? 'available'),
              orElse: () => ProductStatus.available,
            ),
            stockQuantity: (json['product_stock_quantity'] as num?)?.toInt() ?? 1,
            discountPercent: (json['product_discount_percent'] as num?)?.toDouble() ?? 0,
            discountStartDate: json['product_discount_start_date'] != null
                ? DateTime.tryParse(json['product_discount_start_date'] as String)
                : null,
            discountEndDate: json['product_discount_end_date'] != null
                ? DateTime.tryParse(json['product_discount_end_date'] as String)
                : null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            sellerName: json['product_seller_name'] as String?,
            businessName: json['product_business_name'] as String?,
            sellerAvatar: json['product_seller_avatar'] as String?,
            isSellerVerified: json['product_is_seller_verified'] as bool? ?? false,
            campuses: (json['product_campuses'] as List<dynamic>?)
                    ?.map((e) => e as String)
                    .toList() ??
                [],
          );
        }

        if (json['item_category_id'] != null) {
          final catImageUrl = json['category_image_url'] as String?;
          category = Category(
            id: json['item_category_id'] as String,
            name: json['category_name'] as String? ?? '',
            icon: json['category_icon'] as String?,
            colorIndex: (json['category_color_index'] as num?)?.toInt() ?? 0,
            imageUrl: catImageUrl,
            slug: json['category_slug'] as String?,
            createdAt: DateTime.now(),
          );
        }

        itemsMap[collectionId]!.add(CuratedItem(
          id: itemId,
          productId: json['item_product_id'] as String?,
          categoryId: json['item_category_id'] as String?,
          sortOrder: (json['item_sort_order'] as num?)?.toInt() ?? 0,
          product: product,
          category: category,
        ));
      }
    }

    // Attach items to collections
    return collectionsMap.values.map((collection) {
      final items = itemsMap[collection.id] ?? [];
      items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      return CuratedCollection(
        id: collection.id,
        title: collection.title,
        subtitle: collection.subtitle,
        icon: collection.icon,
        imageUrl: collection.imageUrl,
        displayMode: collection.displayMode,
        contentType: collection.contentType,
        maxItems: collection.maxItems,
        isVisible: collection.isVisible,
        sortOrder: collection.sortOrder,
        items: items,
      );
    }).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }
}

class CuratedItem {
  final String id;
  final String? productId;
  final String? categoryId;
  final int sortOrder;
  final Product? product;
  final Category? category;

  CuratedItem({
    required this.id,
    this.productId,
    this.categoryId,
    this.sortOrder = 0,
    this.product,
    this.category,
  });
}
