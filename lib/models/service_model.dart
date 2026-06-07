class Service {
  final String id;
  final String providerId;
  final String? providerName;
  final String? providerAvatar;
  final String title;
  final String? description;
  final String? category;
  final double price;
  final String? priceType;
  final List<String> imageUrls;
  final List<String> institutionCodes;
  final String? status;
  final double? averageRating;
  final int? reviewCount;
  final DateTime createdAt;

  Service({
    required this.id,
    required this.providerId,
    this.providerName,
    this.providerAvatar,
    required this.title,
    this.description,
    this.category,
    required this.price,
    this.priceType,
    this.imageUrls = const [],
    this.institutionCodes = const [],
    this.status,
    this.averageRating,
    this.reviewCount,
    required this.createdAt,
  });

  factory Service.fromJson(Map<String, dynamic> json) {
    return Service(
      id: json['id'] as String,
      providerId: json['provider_id'] as String,
      providerName: json['provider_name'] as String?,
      providerAvatar: json['provider_avatar'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: json['category'] as String?,
      price: (json['price'] as num).toDouble(),
      priceType: json['price_type'] as String?,
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      institutionCodes: (json['institution_codes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String?,
      averageRating: (json['average_rating'] as num?)?.toDouble(),
      reviewCount: (json['review_count'] as num?)?.toInt(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ServiceReview {
  final String id;
  final String serviceId;
  final String reviewerId;
  final String? reviewerName;
  final String? reviewerAvatar;
  final int rating;
  final String? comment;
  final List<String> mediaUrls;
  final DateTime createdAt;

  ServiceReview({
    required this.id,
    required this.serviceId,
    required this.reviewerId,
    this.reviewerName,
    this.reviewerAvatar,
    required this.rating,
    this.comment,
    this.mediaUrls = const [],
    required this.createdAt,
  });

  factory ServiceReview.fromJson(Map<String, dynamic> json) {
    return ServiceReview(
      id: json['id'] as String,
      serviceId: json['service_id'] as String,
      reviewerId: json['reviewer_id'] as String,
      reviewerName: json['reviewer_name'] as String?,
      reviewerAvatar: json['reviewer_avatar'] as String?,
      rating: (json['rating'] as num).toInt(),
      comment: json['comment'] as String?,
      mediaUrls: (json['media_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
