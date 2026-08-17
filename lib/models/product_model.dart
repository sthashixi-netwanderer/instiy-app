class Product {
  final String id;
  final String sellerId;
  final String title;
  final String description;
  final double price;
  final String? categoryId;
  final List<String> imageUrls;
  final List<String> videoUrls;
  final String? thumbnailUrl;
  final ProductCondition condition;
  final ProductStatus status;
  final List<String> campuses;
  final List<Map<String, String>> specifications;
  final DateTime createdAt;
  final DateTime updatedAt;

  final int stockQuantity;
  final String deliveryOption;
  final double deliveryFee;
  final Map<String, double> institutionDeliveryFees;

  // Featured flag
  final bool isFeatured;

  // Clips opt-in
  final bool showOnClips;

  // Which video URL is shown in the Clips feed (null = use videoUrls.first)
  final String? clipVideoUrl;

  // Discount fields
  final double discountPercent;
  final DateTime? discountStartDate;
  final DateTime? discountEndDate;

  // SEO-friendly slug
  final String slug;

  // Review data
  final double? averageRating;
  final int? reviewCount;

  // Joined data
  final String? sellerName;
  final String? sellerAvatar;
  final String? sellerEmail;
  final String? sellerPhone;
  final String? businessName;
  final String? categoryName;
  final bool isSellerVerified;

  Product({
    required this.id,
    required this.sellerId,
    required this.title,
    required this.description,
    required this.price,
    this.categoryId,
    required this.imageUrls,
    this.videoUrls = const [],
    this.thumbnailUrl,
    required this.condition,
    required this.status,
    this.campuses = const [],
    this.specifications = const [],
    required this.createdAt,
    required this.updatedAt,
    this.stockQuantity = 1,
    this.deliveryOption = 'pickup',
    this.deliveryFee = 0.0,
    this.institutionDeliveryFees = const {},
    this.isFeatured = false,
    this.showOnClips = false,
    this.clipVideoUrl,
    this.discountPercent = 0,
    this.discountStartDate,
    this.discountEndDate,
    String? slug,
    this.averageRating,
    this.reviewCount,
    this.sellerName,
    this.sellerAvatar,
    this.sellerEmail,
    this.sellerPhone,
    this.businessName,
    this.categoryName,
    this.isSellerVerified = false,
  }) : slug = slug ?? Product.generateSlug(title);

  /// SEO-friendly slug (stored in DB, falls back to title-derived slug).
  // slug is now a stored field with a default from generateSlug(title)

  /// Generate a URL-safe slug from a title string.
  static String generateSlug(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  /// Extract a UUID from a slug-id string (e.g. "nike-air-max-abc123...").
  /// Falls back to returning the raw string if no UUID is found.
  static String extractId(String slugId) {
    final match = RegExp(
      r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
    ).firstMatch(slugId);
    return match?.group(1) ?? slugId;
  }

  /// The effective thumbnail URL: the seller-selected thumbnail, or the first image as fallback
  String? get effectiveThumbnail =>
      thumbnailUrl ?? (imageUrls.isNotEmpty ? imageUrls.first : null);

  /// Whether the discount is currently active
  bool get isDiscountActive {
    if (discountPercent <= 0) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (discountStartDate != null && discountStartDate!.isAfter(today)) return false;
    if (discountEndDate != null && discountEndDate!.isBefore(today)) return false;
    return true;
  }

  /// The effective price after discount
  double get effectivePrice {
    if (!isDiscountActive) return price;
    return price * (1 - discountPercent / 100);
  }

  /// Whether the product has an attached video
  bool get hasVideo => videoUrls.isNotEmpty;

  /// Seconds until discount expires (null if no active discount)
  int? get discountSecondsRemaining {
    if (!isDiscountActive || discountEndDate == null) return null;
    final now = DateTime.now();
    final end = DateTime(
      discountEndDate!.year,
      discountEndDate!.month,
      discountEndDate!.day,
      23, 59, 59,
    );
    final diff = end.difference(now).inSeconds;
    return diff > 0 ? diff : null;
  }

  Product copyWith({
    double? averageRating,
    int? reviewCount,
    String? slug,
    String? clipVideoUrl,
  }) {
    return Product(
      id: id,
      sellerId: sellerId,
      title: title,
      description: description,
      price: price,
      categoryId: categoryId,
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      thumbnailUrl: thumbnailUrl,
      condition: condition,
      status: status,
      campuses: campuses,
      specifications: specifications,
      createdAt: createdAt,
      updatedAt: updatedAt,
      stockQuantity: stockQuantity,
      deliveryOption: deliveryOption,
      deliveryFee: deliveryFee,
      institutionDeliveryFees: institutionDeliveryFees,
      isFeatured: isFeatured,
      showOnClips: showOnClips,
      clipVideoUrl: clipVideoUrl ?? this.clipVideoUrl,
      discountPercent: discountPercent,
      discountStartDate: discountStartDate,
      discountEndDate: discountEndDate,
      slug: slug ?? this.slug,
      averageRating: averageRating ?? this.averageRating,
      reviewCount: reviewCount ?? this.reviewCount,
      sellerName: sellerName,
      sellerAvatar: sellerAvatar,
      sellerEmail: sellerEmail,
      sellerPhone: sellerPhone,
      businessName: businessName,
      categoryName: categoryName,
      isSellerVerified: isSellerVerified,
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    final sellerMap = json['seller'] as Map<String, dynamic>?;
    final categoryMap = json['category'] as Map<String, dynamic>?;

    final sellerName = json['seller_name'] as String? ?? sellerMap?['full_name'] as String?;
    final sellerAvatar = json['seller_avatar'] as String? ?? sellerMap?['avatar_url'] as String?;
    final sellerEmail = json['seller_email'] as String? ?? sellerMap?['email'] as String?;
    final sellerPhone = json['seller_phone'] as String? ?? sellerMap?['phone_number'] as String?;
    final isSellerVerified = json['is_seller_verified'] as bool? ?? sellerMap?['is_verified'] as bool? ?? false;
    final categoryName = json['category_name'] as String? ?? categoryMap?['name'] as String?;

    final bizProfiles = sellerMap?['business_profiles'];
    String? businessName = json['business_name'] as String?;
    if (businessName == null) {
      if (bizProfiles is List && bizProfiles.isNotEmpty) {
        businessName = (bizProfiles.first as Map<String, dynamic>)['business_name'] as String?;
      } else if (bizProfiles is Map) {
        businessName = bizProfiles['business_name'] as String?;
      }
    }

    return Product(
      id: json['id'] as String,
      sellerId: json['seller_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      price: double.parse(json['price'].toString()),
      categoryId: json['category_id'] as String?,
      imageUrls: List<String>.from(json['image_urls'] ?? []),
      videoUrls: List<String>.from(json['video_urls'] ?? []),
      thumbnailUrl: json['thumbnail_url'] as String?,
      condition: ProductCondition.values.firstWhere(
        (e) => e.name == json['condition'],
        orElse: () => ProductCondition.used,
      ),
      status: ProductStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ProductStatus.available,
      ),
      campuses: _parseCampuses(json['campus']),
      specifications: (json['specifications'] as List<dynamic>?)
              ?.map((e) => Map<String, String>.from(e as Map))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      stockQuantity: (json['stock_quantity'] as num?)?.toInt() ?? 1,
      deliveryOption: json['delivery_option'] as String? ?? 'pickup',
      deliveryFee: json['delivery_fee'] != null ? double.parse(json['delivery_fee'].toString()) : 0.0,
      institutionDeliveryFees: _parseInstitutionFees(json['institution_delivery_fees']),
      isFeatured: json['is_featured'] as bool? ?? false,
      showOnClips: json['show_on_clips'] as bool? ?? false,
      clipVideoUrl: json['clip_video_url'] as String?,
      discountPercent: (json['discount_percent'] as num?)?.toDouble() ?? 0,
      discountStartDate: json['discount_start_date'] != null
          ? DateTime.parse(json['discount_start_date'] as String)
          : null,
      discountEndDate: json['discount_end_date'] != null
          ? DateTime.parse(json['discount_end_date'] as String)
          : null,
      slug: json['slug'] as String?,
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt(),
      sellerName: sellerName,
      sellerAvatar: sellerAvatar,
      sellerEmail: sellerEmail,
      sellerPhone: sellerPhone,
      businessName: businessName,
      categoryName: categoryName,
      isSellerVerified: isSellerVerified,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'seller_id': sellerId,
      'title': title,
      'description': description,
      'price': price,
      'category_id': categoryId,
      'image_urls': imageUrls,
      'video_urls': videoUrls,
      'thumbnail_url': thumbnailUrl,
      'condition': condition.name,
      'status': status.name,
      'campus': campuses.isNotEmpty ? campuses.join(', ') : null,
      'specifications': specifications,
      'stock_quantity': stockQuantity,
      'delivery_option': deliveryOption,
      'delivery_fee': deliveryFee,
      'institution_delivery_fees': institutionDeliveryFees.entries
          .map((e) => {'institution_name': e.key, 'delivery_fee': e.value})
          .toList(),
      'show_on_clips': showOnClips,
      'clip_video_url': clipVideoUrl,
      'discount_percent': discountPercent,
      'discount_start_date': discountStartDate?.toIso8601String().split('T')[0],
      'discount_end_date': discountEndDate?.toIso8601String().split('T')[0],
      'slug': slug,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static List<String> _parseCampuses(dynamic value) {
    if (value == null) return [];
    if (value is List) return value.cast<String>();
    final str = value as String;
    if (str.isEmpty) return [];
    return str.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static Map<String, double> _parseInstitutionFees(dynamic value) {
    if (value == null) return {};
    if (value is List) {
      return {for (final e in value)
        if (e is Map)
          (e['institution_name'] as String?) ?? '' : (e['delivery_fee'] as num?)?.toDouble() ?? 0.0
      }..removeWhere((k, _) => k.isEmpty);
    }
    return {};
  }
}

enum ProductCondition {
  brandNew,
  used,
  refurbished;

  String get displayName {
    switch (this) {
      case ProductCondition.brandNew:
        return 'Brand New';
      case ProductCondition.used:
        return 'Used';
      case ProductCondition.refurbished:
        return 'Refurbished';
    }
  }
}

enum ProductStatus {
  available,
  reserved,
  sold;

  String get displayName {
    switch (this) {
      case ProductStatus.available:
        return 'Available';
      case ProductStatus.reserved:
        return 'Reserved';
      case ProductStatus.sold:
        return 'Sold';
    }
  }
}
