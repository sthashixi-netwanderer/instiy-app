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
  final bool suspended;
  final DateTime? suspendedAt;
  final String? suspendedReportId;
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
    this.suspended = false,
    this.suspendedAt,
    this.suspendedReportId,
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
      suspended: json['suspended'] as bool? ?? false,
      suspendedAt: json['suspended_at'] != null
          ? DateTime.tryParse(json['suspended_at'] as String)
          : null,
      suspendedReportId: json['suspended_report_id'] as String?,
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
      'suspended': suspended,
      'suspended_at': suspendedAt?.toIso8601String(),
      'suspended_report_id': suspendedReportId,
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
    bool? suspended,
    DateTime? suspendedAt,
    String? suspendedReportId,
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
      suspended: suspended ?? this.suspended,
      suspendedAt: suspendedAt ?? this.suspendedAt,
      suspendedReportId: suspendedReportId ?? this.suspendedReportId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
