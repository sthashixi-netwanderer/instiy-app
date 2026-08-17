class CartItem {
  final String id;
  final String productId;
  final String title;
  final String? thumbnail;
  final double price;
  final int quantity;
  final int? stock;
  final String? sellerId;
  final String? sellerName;
  final bool isAvailable;
  final double deliveryFee;

  CartItem({
    required this.id,
    required this.productId,
    required this.title,
    this.thumbnail,
    required this.price,
    required this.quantity,
    this.stock,
    this.sellerId,
    this.sellerName,
    this.isAvailable = true,
    this.deliveryFee = 0.0,
  });

  double get totalPrice => price * quantity;

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      title: json['title'] as String,
      thumbnail: json['thumbnail'] as String?,
      price: (json['price'] as num).toDouble(),
      quantity: (json['quantity'] as num).toInt(),
      stock: (json['stock'] as num?)?.toInt(),
      sellerId: json['seller_id'] as String?,
      sellerName: json['seller_name'] as String?,
      isAvailable: json['is_available'] as bool? ?? true,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
    );
  }

  CartItem copyWith({
    String? id,
    String? productId,
    String? title,
    String? thumbnail,
    double? price,
    int? quantity,
    int? stock,
    String? sellerId,
    String? sellerName,
    bool? isAvailable,
    double? deliveryFee,
  }) {
    return CartItem(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      title: title ?? this.title,
      thumbnail: thumbnail ?? this.thumbnail,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      stock: stock ?? this.stock,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      isAvailable: isAvailable ?? this.isAvailable,
      deliveryFee: deliveryFee ?? this.deliveryFee,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'product_id': productId,
    'title': title,
    'thumbnail': thumbnail,
    'price': price,
    'quantity': quantity,
    'stock': stock,
    'seller_id': sellerId,
    'seller_name': sellerName,
    'is_available': isAvailable,
    'delivery_fee': deliveryFee,
  };
}

class CartState {
  final List<CartItem> items;
  final int itemCount;
  final double subtotalAmount;
  final double deliveryTotal;
  final double totalAmount;
  final bool hasUnavailableItems;

  CartState({
    this.items = const [],
    this.itemCount = 0,
    this.subtotalAmount = 0,
    this.deliveryTotal = 0,
    this.totalAmount = 0,
    this.hasUnavailableItems = false,
  });

  factory CartState.fromJson(Map<String, dynamic> json) {
    return CartState(
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => CartItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      itemCount: (json['item_count'] as num?)?.toInt() ?? 0,
      subtotalAmount: (json['subtotal_amount'] as num?)?.toDouble() ?? 0,
      deliveryTotal: (json['delivery_total'] as num?)?.toDouble() ?? 0,
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      hasUnavailableItems: json['has_unavailable_items'] as bool? ?? false,
    );
  }

  CartState copyWith({
    List<CartItem>? items,
    int? itemCount,
    double? subtotalAmount,
    double? deliveryTotal,
    double? totalAmount,
    bool? hasUnavailableItems,
  }) {
    final newItems = items ?? this.items;
    final newSubtotal = subtotalAmount ?? newItems.fold<double>(0.0, (sum, i) => sum + i.totalPrice);
    final newDelivery = deliveryTotal ?? newItems.fold<double>(0.0, (sum, i) => sum + i.deliveryFee);
    return CartState(
      items: newItems,
      itemCount: itemCount ?? newItems.length,
      subtotalAmount: newSubtotal,
      deliveryTotal: newDelivery,
      totalAmount: totalAmount ?? (newSubtotal + newDelivery),
      hasUnavailableItems: hasUnavailableItems ?? newItems.any((i) => !i.isAvailable),
    );
  }
}
