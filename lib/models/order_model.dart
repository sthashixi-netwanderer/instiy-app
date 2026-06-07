/// Safely converts a dynamic map (from Supabase nested responses) to `Map<String, dynamic>`.
Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  return Map<String, dynamic>.from(value as Map);
}

class OrderItem {
  final String id;
  final String orderId;
  final String? productId;   // nullable — product may have been deleted
  final String productTitle;
  final String? productThumbnail;
  final int quantity;
  final double price;
  final String? deliveryCode;
  final String? status;
  final String? sellerId;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productTitle,
    this.productThumbnail,
    required this.quantity,
    required this.price,
    this.deliveryCode,
    this.status,
    this.sellerId,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      productId: json['product_id'] as String?,          // nullable
      productTitle: json['product_title'] as String,
      productThumbnail: json['product_thumbnail'] as String?,
      quantity: (json['quantity'] as num).toInt(),
      price: double.parse(json['price'].toString()),
      deliveryCode: json['delivery_code'] as String?,
      status: json['status'] as String?,
      sellerId: json['seller_id'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_id': orderId,
    'product_id': productId,   // may be null
    'product_title': productTitle,
    'product_thumbnail': productThumbnail,
    'quantity': quantity,
    'price': price,
    'delivery_code': deliveryCode,
    'status': status,
    'seller_id': sellerId,
  };
}

class Order {
  final String id;
  final String buyerId;
  final String? sellerId;
  final String? sellerName;
  final double totalAmount;
  final double deliveryFee;
  final int itemQuantityTotal;
  final String status;
  final String paymentStatus;
  final String? deliveryMode;
  final String? deliveryInstitution;
  final DateTime createdAt;
  final List<OrderItem> items;

  Order({
    required this.id,
    required this.buyerId,
    this.sellerId,
    this.sellerName,
    required this.totalAmount,
    this.deliveryFee = 0.0,
    required this.itemQuantityTotal,
    required this.status,
    required this.paymentStatus,
    this.deliveryMode,
    this.deliveryInstitution,
    required this.createdAt,
    this.items = const [],
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    // Derive sellerId/sellerName from first order item if available
    final rawItems = json['items'] as List<dynamic>?;
    final firstItem = rawItems?.isNotEmpty == true
        ? _asMap(rawItems!.first)
        : null;

    return Order(
      id: json['id'] as String,
      buyerId: json['buyer_id'] as String,
      // orders table has no seller_id — derive from first item
      sellerId: firstItem?['seller_id'] as String?,
      sellerName: json['seller_name'] as String?,
      totalAmount: double.parse(json['total_amount'].toString()),
      deliveryFee: json['delivery_fee'] != null
          ? double.parse(json['delivery_fee'].toString())
          : 0.0,
      itemQuantityTotal: (json['item_quantity_total'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'pending',
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      deliveryMode: json['delivery_mode'] as String?,
      deliveryInstitution: json['delivery_institution'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      items: rawItems
              ?.map((e) => OrderItem.fromJson(_asMap(e)))
              .toList() ??
          [],
    );
  }
}
