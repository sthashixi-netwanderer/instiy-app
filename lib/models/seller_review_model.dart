class ProductReview {
  final String id;
  final String productId;
  final String reviewerId;
  final int rating;
  final String? comment;
  final List<String> mediaUrls;
  final int helpfulCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? reviewerName;
  final String? reviewerAvatar;
  final String? productTitle;
  final String? productThumbnail;
  final String? parentId;
  List<ProductReview> replies;

  ProductReview({
    required this.id,
    required this.productId,
    required this.reviewerId,
    required this.rating,
    this.comment,
    this.mediaUrls = const [],
    this.helpfulCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.reviewerName,
    this.reviewerAvatar,
    this.productTitle,
    this.productThumbnail,
    this.parentId,
    this.replies = const [],
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic>? reviewer;
    if (json['reviewer'] != null) {
      reviewer = json['reviewer'] as Map<String, dynamic>?;
    }

    Map<String, dynamic>? product;
    if (json['product'] != null) {
      product = json['product'] as Map<String, dynamic>?;
    }

    return ProductReview(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      reviewerId: json['reviewer_id'] as String,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String?,
      mediaUrls: (json['media_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      helpfulCount: (json['helpful_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      reviewerName: reviewer?['full_name'] as String?,
      reviewerAvatar: reviewer?['avatar_url'] as String?,
      productTitle: product?['title'] as String?,
      productThumbnail: product?['image_urls'] != null
          ? ((product!['image_urls'] as List).isNotEmpty
              ? (product['image_urls'] as List).first as String
              : null)
          : null,
      parentId: json['parent_id'] as String?,
      replies: [],
    );
  }

  /// Parses flat RPC response from get_seller_store_reviews
  factory ProductReview.fromRpcJson(Map<String, dynamic> json) {
    final replyText = json['reply'] as String?;
    return ProductReview(
      id: json['id'] as String,
      productId: json['product_id'] as String,
      reviewerId: json['reviewer_id'] as String,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String?,
      mediaUrls: (json['media_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      helpfulCount: (json['helpful_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      reviewerName: json['reviewer_name'] as String?,
      reviewerAvatar: json['reviewer_avatar'] as String?,
      productTitle: json['product_title'] as String?,
      productThumbnail: json['product_thumbnail'] as String?,
      parentId: json['parent_id'] as String?,
      replies: replyText != null && replyText.isNotEmpty
          ? [ProductReview(
              id: '${json['id']}_reply',
              productId: json['product_id'] as String,
              reviewerId: '',
              rating: 0,
              comment: replyText,
              createdAt: DateTime.parse(json['created_at'] as String),
              updatedAt: DateTime.parse(json['updated_at'] as String),
            )]
          : [],
    );
  }

  String? get reply => replies.isNotEmpty ? replies.first.comment : null;
}

class DashboardStats {
  final int totalProducts;
  final double averageRating;
  final int activeViews;
  final int followersCount;
  final int pendingOrders;
  final int newReviews;
  final int totalSold;
  final int activeListings;
  final double totalRevenue;

  DashboardStats({
    this.totalProducts = 0,
    this.averageRating = 0,
    this.activeViews = 0,
    this.followersCount = 0,
    this.pendingOrders = 0,
    this.newReviews = 0,
    this.totalSold = 0,
    this.activeListings = 0,
    this.totalRevenue = 0,
  });
}
