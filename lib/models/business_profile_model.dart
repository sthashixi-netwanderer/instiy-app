class BusinessProfile {
  final String id;
  final String sellerId;
  final String? bannerUrl;
  final String? businessName;
  final String? description;
  final String? locationUrl;
  final String? digitalAddress;
  final bool qrCodePublic;
  final String? university;

  /// Seller's profile image, joined from `users.avatar_url`.
  final String? avatarUrl;
  final List<StorePhoneNumber> phoneNumbers;
  final DateTime createdAt;
  final DateTime updatedAt;

  BusinessProfile({
    required this.id,
    required this.sellerId,
    this.bannerUrl,
    this.businessName,
    this.description,
    this.locationUrl,
    this.digitalAddress,
    this.qrCodePublic = false,
    this.university,
    this.avatarUrl,
    this.phoneNumbers = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    List<StorePhoneNumber> phones = [];
    if (json['phone_numbers'] != null) {
      final phoneList = json['phone_numbers'] as List;
      phones = phoneList.map((p) => StorePhoneNumber.fromJson(p as Map<String, dynamic>)).toList();
    }

    return BusinessProfile(
      id: json['id'] as String,
      sellerId: json['seller_id'] as String,
      bannerUrl: json['banner_url'] as String?,
      businessName: json['business_name'] as String?,
      description: json['description'] as String?,
      locationUrl: json['location_url'] as String?,
      digitalAddress: json['digital_address'] as String?,
      qrCodePublic: json['qr_code_public'] as bool? ?? false,
      university: json['university'] as String? ??
          (json['users'] as Map<String, dynamic>?)?['university'] as String?,
      avatarUrl:
          (json['users'] as Map<String, dynamic>?)?['avatar_url'] as String?,
      phoneNumbers: phones,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'seller_id': sellerId,
      'banner_url': bannerUrl,
      'business_name': businessName,
      'description': description,
      'location_url': locationUrl,
      'digital_address': digitalAddress,
      'phone_numbers': phoneNumbers.map((p) => p.toJson()).toList(),
    };
  }

  BusinessProfile copyWith({
    String? bannerUrl,
    String? businessName,
    String? description,
    String? locationUrl,
    String? digitalAddress,
    bool? qrCodePublic,
    List<StorePhoneNumber>? phoneNumbers,
  }) {
    return BusinessProfile(
      id: id,
      sellerId: sellerId,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      businessName: businessName ?? this.businessName,
      description: description ?? this.description,
      locationUrl: locationUrl ?? this.locationUrl,
      digitalAddress: digitalAddress ?? this.digitalAddress,
      qrCodePublic: qrCodePublic ?? this.qrCodePublic,
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

class StorePhoneNumber {
  final String number;
  final String label;
  final bool isWhatsApp;

  StorePhoneNumber({
    required this.number,
    this.label = 'Primary',
    this.isWhatsApp = false,
  });

  factory StorePhoneNumber.fromJson(Map<String, dynamic> json) {
    return StorePhoneNumber(
      number: json['number'] as String,
      label: json['label'] as String? ?? 'Primary',
      isWhatsApp: json['is_whatsapp'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'number': number,
      'label': label,
      'is_whatsapp': isWhatsApp,
    };
  }
}

class StoreStats {
  final int followerCount;
  final int reviewCount;
  final double averageRating;
  final int totalProducts;

  StoreStats({
    this.followerCount = 0,
    this.reviewCount = 0,
    this.averageRating = 0,
    this.totalProducts = 0,
  });

  factory StoreStats.fromJson(Map<String, dynamic> json) {
    return StoreStats(
      followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      averageRating: (json['average_rating'] as num?)?.toDouble() ?? 0,
      totalProducts: (json['total_products'] as num?)?.toInt() ?? 0,
    );
  }
}
