/// Pricing tier of a service package (Fiverr-style).
enum ServiceTier { basic, standard, premium }

extension ServiceTierX on ServiceTier {
  String get displayName {
    switch (this) {
      case ServiceTier.basic:
        return 'Basic';
      case ServiceTier.standard:
        return 'Standard';
      case ServiceTier.premium:
        return 'Premium';
    }
  }

  int get sortOrder {
    switch (this) {
      case ServiceTier.basic:
        return 0;
      case ServiceTier.standard:
        return 1;
      case ServiceTier.premium:
        return 2;
    }
  }

  static ServiceTier fromName(String? name) {
    return ServiceTier.values.firstWhere(
      (t) => t.name == name,
      orElse: () => ServiceTier.basic,
    );
  }
}

/// Lifecycle of a service listing. Providers manage this from the
/// Services screen (the only place their dashboard is reachable).
enum ServiceStatus { active, paused, inactive }

extension ServiceStatusX on ServiceStatus {
  String get displayName {
    switch (this) {
      case ServiceStatus.active:
        return 'Active';
      case ServiceStatus.paused:
        return 'Paused';
      case ServiceStatus.inactive:
        return 'Inactive';
    }
  }

  static ServiceStatus fromName(String? name) {
    return ServiceStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ServiceStatus.active,
    );
  }
}

/// One pricing tier of a service. The cheapest tier defines the service's
/// starting price (kept in sync by the sync_services_start_price trigger).
class ServicePackage {
  final String? id;
  final String? serviceId;
  final ServiceTier tier;
  final String name;
  final String description;
  final double price;
  final int deliveryDays;
  final int revisions;
  final bool isPopular;
  final DateTime? createdAt;

  ServicePackage({
    this.id,
    this.serviceId,
    required this.tier,
    required this.name,
    this.description = '',
    required this.price,
    this.deliveryDays = 3,
    this.revisions = 1,
    this.isPopular = false,
    this.createdAt,
  });

  factory ServicePackage.fromJson(Map<String, dynamic> json) {
    return ServicePackage(
      id: json['id'] as String?,
      serviceId: json['service_id'] as String?,
      tier: ServiceTierX.fromName(json['tier'] as String?),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      deliveryDays: (json['delivery_days'] as num?)?.toInt() ?? 3,
      revisions: (json['revisions'] as num?)?.toInt() ?? 1,
      isPopular: json['is_popular'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson({String? serviceId}) {
    return {
      'service_id': ?serviceId,
      'tier': tier.name,
      'name': name,
      'description': description,
      'price': price,
      'delivery_days': deliveryDays,
      'revisions': revisions,
      'is_popular': isPopular,
    };
  }

  ServicePackage copyWith({
    String? id,
    String? serviceId,
    ServiceTier? tier,
    String? name,
    String? description,
    double? price,
    int? deliveryDays,
    int? revisions,
    bool? isPopular,
  }) {
    return ServicePackage(
      id: id ?? this.id,
      serviceId: serviceId ?? this.serviceId,
      tier: tier ?? this.tier,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      deliveryDays: deliveryDays ?? this.deliveryDays,
      revisions: revisions ?? this.revisions,
      isPopular: isPopular ?? this.isPopular,
      createdAt: createdAt,
    );
  }
}

class Service {
  final String id;
  final String providerId;
  final String? providerName;
  final String? providerAvatar;

  /// Provider's marketplace bio, shown under their name on the detail
  /// screen. Set at opt-in, editable from the Services screen.
  final String? providerBio;
  final String title;
  final String? description;
  final String? categoryId;
  final String? categoryName;
  final String? categorySlug;
  final double price;
  final String? priceType;
  final int? deliveryDays;
  final List<String> imageUrls;
  final List<String> institutionCodes;
  final List<String> searchTags;
  final ServiceStatus status;
  final double? averageRating;
  final int? reviewCount;
  final DateTime createdAt;
  final List<ServicePackage> packages;

  Service({
    required this.id,
    required this.providerId,
    this.providerName,
    this.providerAvatar,
    this.providerBio,
    required this.title,
    this.description,
    this.categoryId,
    this.categoryName,
    this.categorySlug,
    required this.price,
    this.priceType,
    this.deliveryDays,
    this.imageUrls = const [],
    this.institutionCodes = const [],
    this.searchTags = const [],
    this.status = ServiceStatus.active,
    this.averageRating,
    this.reviewCount,
    required this.createdAt,
    this.packages = const [],
  });

  bool get isActive => status == ServiceStatus.active;

  /// Cheapest package price when tiers exist, otherwise the base price.
  double get startingPrice => packages.isEmpty
      ? price
      : packages.map((p) => p.price).reduce((a, b) => a < b ? a : b);

  /// Fastest delivery across packages (or the service-level estimate).
  int? get minDeliveryDays => packages.isEmpty
      ? deliveryDays
      : packages
            .map((p) => p.deliveryDays)
            .reduce((a, b) => a < b ? a : b);

  /// Packages ordered Basic → Standard → Premium.
  List<ServicePackage> get sortedPackages {
    final list = [...packages]..sort((a, b) => a.tier.sortOrder.compareTo(
      b.tier.sortOrder,
    ));
    return list;
  }

  factory Service.fromJson(Map<String, dynamic> json) {
    final provider = json['provider'] as Map<String, dynamic>?;
    final category = json['category'] as Map<String, dynamic>?;
    return Service(
      id: json['id'] as String,
      providerId: json['provider_id'] as String,
      providerName:
          provider?['full_name'] as String? ??
          json['provider_name'] as String?,
      providerAvatar:
          provider?['avatar_url'] as String? ??
          json['provider_avatar'] as String?,
      providerBio: provider?['service_provider_bio'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      categoryId:
          json['category_id'] as String? ?? json['categoryId'] as String?,
      categoryName:
          category?['name'] as String? ?? json['category'] as String?,
      categorySlug: category?['slug'] as String?,
      price: (json['price'] as num).toDouble(),
      priceType: json['price_type'] as String?,
      deliveryDays: (json['delivery_days'] as num?)?.toInt(),
      imageUrls:
          (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      institutionCodes:
          (json['institution_codes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      searchTags:
          (json['search_tags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: ServiceStatusX.fromName(json['status'] as String?),
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
      packages:
          (json['packages'] as List<dynamic>?)
              ?.map(
                (e) => ServicePackage.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }

  /// Row payload for insert/update. The denormalized `category` text column
  /// is kept alongside the FK for backward compatibility.
  Map<String, dynamic> toJson({bool includeProvider = false}) {
    return {
      if (includeProvider) 'provider_id': providerId,
      'title': title,
      'description': description,
      'category': categoryName,
      'category_id': categoryId,
      'price': price,
      'price_type': priceType ?? 'fixed',
      'delivery_days': deliveryDays,
      'image_urls': imageUrls,
      'search_tags': searchTags,
      'status': status.name,
    };
  }

  Service copyWith({
    String? providerBio,
    String? title,
    String? description,
    String? categoryId,
    String? categoryName,
    double? price,
    String? priceType,
    int? deliveryDays,
    List<String>? imageUrls,
    List<String>? institutionCodes,
    List<String>? searchTags,
    ServiceStatus? status,
    List<ServicePackage>? packages,
  }) {
    return Service(
      id: id,
      providerId: providerId,
      providerName: providerName,
      providerAvatar: providerAvatar,
      providerBio: providerBio ?? this.providerBio,
      title: title ?? this.title,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      categorySlug: categorySlug,
      price: price ?? this.price,
      priceType: priceType ?? this.priceType,
      deliveryDays: deliveryDays ?? this.deliveryDays,
      imageUrls: imageUrls ?? this.imageUrls,
      institutionCodes: institutionCodes ?? this.institutionCodes,
      searchTags: searchTags ?? this.searchTags,
      status: status ?? this.status,
      averageRating: averageRating,
      reviewCount: reviewCount,
      createdAt: createdAt,
      packages: packages ?? this.packages,
    );
  }
}

/// A customer review on a service. Reviewers manage (edit/delete) their own
/// rows; the services.average_rating / review_count rollups are maintained
/// by the sync_service_review_stats trigger.
class ServiceReview {
  final String id;
  final String serviceId;
  final String reviewerId;
  final String? reviewerName;
  final String? reviewerAvatar;
  final int rating;
  final String? comment;
  final int helpfulCount;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ServiceReview({
    required this.id,
    required this.serviceId,
    required this.reviewerId,
    this.reviewerName,
    this.reviewerAvatar,
    required this.rating,
    this.comment,
    this.helpfulCount = 0,
    required this.createdAt,
    this.updatedAt,
  });

  factory ServiceReview.fromJson(Map<String, dynamic> json) {
    final reviewer = json['reviewer'] as Map<String, dynamic>?;
    return ServiceReview(
      id: json['id'] as String,
      serviceId: json['service_id'] as String,
      reviewerId: json['reviewer_id'] as String,
      reviewerName:
          reviewer?['full_name'] as String? ??
          json['reviewer_name'] as String?,
      reviewerAvatar:
          reviewer?['avatar_url'] as String? ??
          json['reviewer_avatar'] as String?,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String?,
      helpfulCount: (json['helpful_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }
}
