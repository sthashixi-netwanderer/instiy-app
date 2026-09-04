/// Admin-configurable referral program settings, stored as the
/// `referral_program` key in platform_settings.
class ReferralProgramConfig {
  final bool enabled;
  final double minPurchaseAmountGhs;
  final int pointsPerReferral;

  const ReferralProgramConfig({
    this.enabled = true,
    this.minPurchaseAmountGhs = 50,
    this.pointsPerReferral = 500,
  });

  factory ReferralProgramConfig.fromJson(Map<String, dynamic> json) {
    return ReferralProgramConfig(
      enabled: json['enabled'] as bool? ?? true,
      minPurchaseAmountGhs:
          (json['min_purchase_amount_ghs'] as num?)?.toDouble() ?? 50,
      pointsPerReferral:
          (json['points_per_referral'] as num?)?.toInt() ?? 500,
    );
  }
}

/// The signed-in user's referral snapshot shown on the referral screen.
class ReferralSummary {
  final String referralCode;
  final int points;
  final int totalReferred;
  final int qualifiedCount;

  const ReferralSummary({
    required this.referralCode,
    required this.points,
    required this.totalReferred,
    required this.qualifiedCount,
  });

  /// Shareable link — opens the register screen with the code
  /// pre-filled (or the referral screen when already signed in).
  String get link => 'https://instiy.com/referral?code=$referralCode';
}

/// One row of the user's referral history.
class ReferralRecord {
  final String id;
  final String status; // 'registered' | 'qualified'
  final int pointsAwarded;
  final DateTime createdAt;
  final DateTime? qualifiedAt;
  final String? referredName;
  final String? referredAvatar;

  const ReferralRecord({
    required this.id,
    required this.status,
    required this.pointsAwarded,
    required this.createdAt,
    this.qualifiedAt,
    this.referredName,
    this.referredAvatar,
  });

  bool get isQualified => status == 'qualified';

  factory ReferralRecord.fromJson(Map<String, dynamic> json) {
    final referred = json['referred'] as Map<String, dynamic>?;
    return ReferralRecord(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'registered',
      pointsAwarded: (json['points_awarded'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      qualifiedAt: json['qualified_at'] != null
          ? DateTime.tryParse(json['qualified_at'] as String)
          : null,
      referredName: referred?['full_name'] as String?,
      referredAvatar: referred?['avatar_url'] as String?,
    );
  }
}

/// The signed-in user's own reward for having been referred (the row
/// where they are the referred user, if any).
class ReferredReward {
  final String id;
  final String status; // 'registered' | 'qualified'
  final int refereePoints;
  final DateTime? awardedAt;
  final DateTime? qualifiedAt;
  final String? referrerName;

  const ReferredReward({
    required this.id,
    required this.status,
    required this.refereePoints,
    this.awardedAt,
    this.qualifiedAt,
    this.referrerName,
  });

  bool get isAwarded => awardedAt != null;
  bool get isQualified => status == 'qualified';

  factory ReferredReward.fromJson(Map<String, dynamic> json) {
    final referrer = json['referrer'] as Map<String, dynamic>?;
    return ReferredReward(
      id: json['id'] as String,
      status: json['status'] as String? ?? 'registered',
      refereePoints: (json['referee_points'] as num?)?.toInt() ?? 0,
      awardedAt: json['referee_awarded_at'] != null
          ? DateTime.tryParse(json['referee_awarded_at'] as String)
          : null,
      qualifiedAt: json['qualified_at'] != null
          ? DateTime.tryParse(json['qualified_at'] as String)
          : null,
      referrerName: referrer?['full_name'] as String?,
    );
  }
}
