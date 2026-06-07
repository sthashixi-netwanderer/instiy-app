import 'product_model.dart';

enum DraftStatus {
  draft,
  publishing,
  failed;

  String get displayName {
    switch (this) {
      case DraftStatus.draft:
        return 'Draft';
      case DraftStatus.publishing:
        return 'Publishing';
      case DraftStatus.failed:
        return 'Failed';
    }
  }
}

class DraftListing {
  final String id;
  final String title;
  final String description;
  final double price;
  final String? categoryId;
  final List<String> imagePaths;
  final List<String> videoPaths;
  final int thumbnailIndex;
  final ProductCondition? condition;
  final List<String> campuses;
  final List<Map<String, String>> specifications;
  final int stockQuantity;
  final String deliveryOption;
  final double deliveryFee;
  final Map<String, double> institutionDeliveryFees;
  final double discountPercent;
  final DateTime? discountStartDate;
  final DateTime? discountEndDate;
  final DraftStatus status;
  final String? errorMessage;
  final double progress; // 0.0 to 1.0 for publish progress
  final DateTime savedAt;

  const DraftListing({
    required this.id,
    required this.title,
    this.description = '',
    this.price = 0,
    this.categoryId,
    this.imagePaths = const [],
    this.videoPaths = const [],
    this.thumbnailIndex = 0,
    this.condition,
    this.campuses = const [],
    this.specifications = const [],
    this.stockQuantity = 1,
    this.deliveryOption = 'pickup',
    this.deliveryFee = 0,
    this.institutionDeliveryFees = const {},
    this.discountPercent = 0,
    this.discountStartDate,
    this.discountEndDate,
    this.status = DraftStatus.draft,
    this.errorMessage,
    this.progress = 0.0,
    required this.savedAt,
  });

  DraftListing copyWith({
    String? title,
    String? description,
    double? price,
    String? categoryId,
    List<String>? imagePaths,
    List<String>? videoPaths,
    int? thumbnailIndex,
    ProductCondition? condition,
    List<String>? campuses,
    List<Map<String, String>>? specifications,
    int? stockQuantity,
    String? deliveryOption,
    double? deliveryFee,
    Map<String, double>? institutionDeliveryFees,
    double? discountPercent,
    DateTime? discountStartDate,
    DateTime? discountEndDate,
    DraftStatus? status,
    String? errorMessage,
    double? progress,
  }) {
    return DraftListing(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      price: price ?? this.price,
      categoryId: categoryId ?? this.categoryId,
      imagePaths: imagePaths ?? this.imagePaths,
      videoPaths: videoPaths ?? this.videoPaths,
      thumbnailIndex: thumbnailIndex ?? this.thumbnailIndex,
      condition: condition ?? this.condition,
      campuses: campuses ?? this.campuses,
      specifications: specifications ?? this.specifications,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      deliveryOption: deliveryOption ?? this.deliveryOption,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      institutionDeliveryFees: institutionDeliveryFees ?? this.institutionDeliveryFees,
      discountPercent: discountPercent ?? this.discountPercent,
      discountStartDate: discountStartDate ?? this.discountStartDate,
      discountEndDate: discountEndDate ?? this.discountEndDate,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      savedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'price': price,
      'categoryId': categoryId,
      'imagePaths': imagePaths,
      'videoPaths': videoPaths,
      'thumbnailIndex': thumbnailIndex,
      'condition': condition?.name,
      'campuses': campuses,
      'specifications': specifications,
      'stockQuantity': stockQuantity,
      'deliveryOption': deliveryOption,
      'deliveryFee': deliveryFee,
      'institutionDeliveryFees': institutionDeliveryFees,
      'discountPercent': discountPercent,
      'discountStartDate': discountStartDate?.toIso8601String(),
      'discountEndDate': discountEndDate?.toIso8601String(),
      'status': status.name,
      'errorMessage': errorMessage,
      'progress': progress,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  factory DraftListing.fromJson(Map<String, dynamic> json) {
    return DraftListing(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      categoryId: json['categoryId'] as String?,
      imagePaths: (json['imagePaths'] as List?)?.cast<String>() ?? [],
      videoPaths: (json['videoPaths'] as List?)?.cast<String>() ?? [],
      thumbnailIndex: json['thumbnailIndex'] as int? ?? 0,
      condition: json['condition'] != null
          ? ProductCondition.values.firstWhere(
              (e) => e.name == json['condition'],
              orElse: () => ProductCondition.used,
            )
          : null,
      campuses: (json['campuses'] as List?)?.cast<String>() ?? [],
      specifications: (json['specifications'] as List?)
              ?.map((e) => Map<String, String>.from(e as Map))
              .toList() ??
          [],
      stockQuantity: json['stockQuantity'] as int? ?? 1,
      deliveryOption: json['deliveryOption'] as String? ?? 'pickup',
      deliveryFee: (json['deliveryFee'] as num?)?.toDouble() ?? 0,
      institutionDeliveryFees: (json['institutionDeliveryFees'] as Map?)
              ?.map((k, v) => MapEntry(k as String, (v as num).toDouble())) ??
          {},
      discountPercent: (json['discountPercent'] as num?)?.toDouble() ?? 0,
      discountStartDate: json['discountStartDate'] != null
          ? DateTime.tryParse(json['discountStartDate'] as String)
          : null,
      discountEndDate: json['discountEndDate'] != null
          ? DateTime.tryParse(json['discountEndDate'] as String)
          : null,
      status: DraftStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DraftStatus.draft,
      ),
      errorMessage: json['errorMessage'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      savedAt: json['savedAt'] != null
          ? DateTime.tryParse(json['savedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
