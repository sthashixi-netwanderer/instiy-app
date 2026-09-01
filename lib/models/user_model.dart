class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String walletTag;
  final String? avatarUrl;
  final String? university;
  final String? bio;
  final String? phoneNumber;
  final bool isVerified;
  final bool isSeller;
  final bool isServiceProvider;
  final bool suspended;
  final DateTime? suspendedAt;
  final String? suspendedReportId;

  /// This user's shareable referral code (generated at signup).
  final String? referralCode;

  /// Lifetime referral points — awarded when referred users' orders
  /// are delivered, reversed if the order is refunded.
  final int referralPoints;

  final DateTime createdAt;
  final DateTime updatedAt;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.walletTag,
    this.avatarUrl,
    this.university,
    this.bio,
    this.phoneNumber,
    this.isVerified = false,
    this.isSeller = false,
    this.isServiceProvider = false,
    this.suspended = false,
    this.suspendedAt,
    this.suspendedReportId,
    this.referralCode,
    this.referralPoints = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      walletTag: json['wallet_tag'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String?,
      university: json['university'] as String?,
      bio: json['bio'] as String?,
      phoneNumber: json['phone_number'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      isSeller: json['is_seller'] as bool? ?? false,
      isServiceProvider: json['is_service_provider'] as bool? ?? false,
      suspended: json['suspended'] as bool? ?? false,
      suspendedAt: json['suspended_at'] != null
          ? DateTime.tryParse(json['suspended_at'] as String)
          : null,
      suspendedReportId: json['suspended_report_id'] as String?,
      referralCode: json['referral_code'] as String?,
      referralPoints: (json['referral_points'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'wallet_tag': walletTag,
      'avatar_url': avatarUrl,
      'university': university,
      'bio': bio,
      'phone_number': phoneNumber,
      'is_verified': isVerified,
      'is_seller': isSeller,
      'is_service_provider': isServiceProvider,
      'suspended': suspended,
      'suspended_at': suspendedAt?.toIso8601String(),
      'suspended_report_id': suspendedReportId,
      'referral_code': referralCode,
      'referral_points': referralPoints,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  AppUser copyWith({
    String? fullName,
    String? walletTag,
    String? avatarUrl,
    String? university,
    String? bio,
    String? phoneNumber,
    bool? isVerified,
    bool? isSeller,
    bool? isServiceProvider,
    bool? suspended,
    DateTime? suspendedAt,
    String? suspendedReportId,
    String? referralCode,
    int? referralPoints,
  }) {
    return AppUser(
      id: id,
      email: email,
      fullName: fullName ?? this.fullName,
      walletTag: walletTag ?? this.walletTag,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      university: university ?? this.university,
      bio: bio ?? this.bio,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      isVerified: isVerified ?? this.isVerified,
      isSeller: isSeller ?? this.isSeller,
      isServiceProvider: isServiceProvider ?? this.isServiceProvider,
      suspended: suspended ?? this.suspended,
      suspendedAt: suspendedAt ?? this.suspendedAt,
      suspendedReportId: suspendedReportId ?? this.suspendedReportId,
      referralCode: referralCode ?? this.referralCode,
      referralPoints: referralPoints ?? this.referralPoints,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
