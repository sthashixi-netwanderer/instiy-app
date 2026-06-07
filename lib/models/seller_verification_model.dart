class SellerVerification {
  final String id;
  final String userId;
  final DateTime dateOfBirth;
  final int yearOfEntrance;
  final int graduationYear;
  final String residentialAddress;
  final String? digitalAddress;
  final String studentIdFrontUrl;
  final String studentIdBackUrl;
  final String liveVideoUrl;
  final String status;
  final String? adminNotes;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  SellerVerification({
    required this.id,
    required this.userId,
    required this.dateOfBirth,
    required this.yearOfEntrance,
    required this.graduationYear,
    required this.residentialAddress,
    this.digitalAddress,
    required this.studentIdFrontUrl,
    required this.studentIdBackUrl,
    required this.liveVideoUrl,
    required this.status,
    this.adminNotes,
    this.reviewedBy,
    this.reviewedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SellerVerification.fromJson(Map<String, dynamic> json) {
    return SellerVerification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      dateOfBirth: DateTime.parse(json['date_of_birth'] as String),
      yearOfEntrance: json['year_of_entrance'] as int,
      graduationYear: json['graduation_year'] as int,
      residentialAddress: json['residential_address'] as String,
      digitalAddress: json['digital_address'] as String?,
      studentIdFrontUrl: json['student_id_front_url'] as String,
      studentIdBackUrl: json['student_id_back_url'] as String,
      liveVideoUrl: json['live_video_url'] as String,
      status: json['status'] as String,
      adminNotes: json['admin_notes'] as String?,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
  bool get isCancelled => status == 'cancelled';
  bool get isRevoked => status == 'revoked';

  String get statusDisplayName {
    switch (status) {
      case 'pending':
        return 'Under Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'cancelled':
        return 'Cancelled';
      case 'revoked':
        return 'Revoked';
      default:
        return status;
    }
  }
}
