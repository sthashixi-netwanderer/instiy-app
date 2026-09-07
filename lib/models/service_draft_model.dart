import 'service_model.dart';

enum ServiceDraftStatus {
  draft,
  publishing,
  failed;
}

/// On-device snapshot of a service listing publish. The service wizard saves
/// this (status: publishing) right before popping, so the background upload
/// can report progress into the My Services tab and a publish interrupted by
/// an app kill surfaces as failed with the stored error.
class ServiceDraftListing {
  final String id;
  final String title;
  final String description;
  final String? categoryId;
  final String? categoryName;
  final List<String> imagePaths;
  final List<String> videoPaths;
  final bool packagesEnabled;

  /// Serialized [ServicePackage] payloads — see [servicePackages].
  final List<Map<String, dynamic>> packages;

  /// Price used when [packagesEnabled] is false (services.price is NOT NULL).
  final double basePrice;
  final int? deliveryDays;
  final List<String> institutionCodes;
  final List<String> searchTags;
  final bool showOnClips;

  /// Index of the clip video among the newly picked videos (-1 = none).
  final int clipVideoIndex;
  final ServiceDraftStatus status;
  final String? errorMessage;
  final double progress; // 0.0 to 1.0 for publish progress
  final DateTime savedAt;

  const ServiceDraftListing({
    required this.id,
    required this.title,
    this.description = '',
    this.categoryId,
    this.categoryName,
    this.imagePaths = const [],
    this.videoPaths = const [],
    this.packagesEnabled = true,
    this.packages = const [],
    this.basePrice = 0,
    this.deliveryDays,
    this.institutionCodes = const [],
    this.searchTags = const [],
    this.showOnClips = false,
    this.clipVideoIndex = -1,
    this.status = ServiceDraftStatus.draft,
    this.errorMessage,
    this.progress = 0.0,
    required this.savedAt,
  });

  List<ServicePackage> get servicePackages => packages
      .map((p) => ServicePackage.fromJson(Map<String, dynamic>.from(p)))
      .toList();

  ServiceDraftListing copyWith({
    String? title,
    String? description,
    String? categoryId,
    String? categoryName,
    List<String>? imagePaths,
    List<String>? videoPaths,
    bool? packagesEnabled,
    List<Map<String, dynamic>>? packages,
    double? basePrice,
    int? deliveryDays,
    List<String>? institutionCodes,
    List<String>? searchTags,
    bool? showOnClips,
    int? clipVideoIndex,
    ServiceDraftStatus? status,
    String? errorMessage,
    double? progress,
  }) {
    return ServiceDraftListing(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryName: categoryName ?? this.categoryName,
      imagePaths: imagePaths ?? this.imagePaths,
      videoPaths: videoPaths ?? this.videoPaths,
      packagesEnabled: packagesEnabled ?? this.packagesEnabled,
      packages: packages ?? this.packages,
      basePrice: basePrice ?? this.basePrice,
      deliveryDays: deliveryDays ?? this.deliveryDays,
      institutionCodes: institutionCodes ?? this.institutionCodes,
      searchTags: searchTags ?? this.searchTags,
      showOnClips: showOnClips ?? this.showOnClips,
      clipVideoIndex: clipVideoIndex ?? this.clipVideoIndex,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      progress: progress ?? this.progress,
      // Bumped on every save so stale detection measures time since the
      // last progress update, not since the publish started.
      savedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'imagePaths': imagePaths,
      'videoPaths': videoPaths,
      'packagesEnabled': packagesEnabled,
      'packages': packages,
      'basePrice': basePrice,
      'deliveryDays': deliveryDays,
      'institutionCodes': institutionCodes,
      'searchTags': searchTags,
      'showOnClips': showOnClips,
      'clipVideoIndex': clipVideoIndex,
      'status': status.name,
      'errorMessage': errorMessage,
      'progress': progress,
      'savedAt': savedAt.toIso8601String(),
    };
  }

  factory ServiceDraftListing.fromJson(Map<String, dynamic> json) {
    return ServiceDraftListing(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      categoryId: json['categoryId'] as String?,
      categoryName: json['categoryName'] as String?,
      imagePaths: (json['imagePaths'] as List?)?.cast<String>() ?? [],
      videoPaths: (json['videoPaths'] as List?)?.cast<String>() ?? [],
      packagesEnabled: json['packagesEnabled'] as bool? ?? true,
      packages: (json['packages'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      basePrice: (json['basePrice'] as num?)?.toDouble() ?? 0,
      deliveryDays: (json['deliveryDays'] as num?)?.toInt(),
      institutionCodes: (json['institutionCodes'] as List?)?.cast<String>() ?? [],
      searchTags: (json['searchTags'] as List?)?.cast<String>() ?? [],
      showOnClips: json['showOnClips'] as bool? ?? false,
      clipVideoIndex: json['clipVideoIndex'] as int? ?? -1,
      status: ServiceDraftStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ServiceDraftStatus.draft,
      ),
      errorMessage: json['errorMessage'] as String?,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      savedAt: json['savedAt'] != null
          ? DateTime.tryParse(json['savedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
