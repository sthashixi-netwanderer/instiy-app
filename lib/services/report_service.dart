import 'supabase_service.dart';
import 'email_service.dart';
import 'auth_service.dart';

class ReportService {
  // ── User report categories (from chat) ──────────────────────
  static const Map<String, ReportCategory> categories = {
    'spam': ReportCategory(
      id: 'spam',
      label: 'Spam',
      description: 'Unsolicited or bulk messages',
      icon: 'mail',
    ),
    'harassment': ReportCategory(
      id: 'harassment',
      label: 'Harassment',
      description: 'Bullying, threats, intimidation',
      icon: 'alertTriangle',
    ),
    'scam': ReportCategory(
      id: 'scam',
      label: 'Scam',
      description: 'Fraud, fake listings, phishing',
      icon: 'circleAlert',
    ),
    'inappropriate_content': ReportCategory(
      id: 'inappropriate_content',
      label: 'Inappropriate Content',
      description: 'Offensive or explicit material',
      icon: 'eye',
    ),
    'fake_account': ReportCategory(
      id: 'fake_account',
      label: 'Fake Account',
      description: 'Impersonation, fake profile',
      icon: 'user',
    ),
    'hate_speech': ReportCategory(
      id: 'hate_speech',
      label: 'Hate Speech',
      description: 'Discriminatory language',
      icon: 'messageSquare',
    ),
    'violence': ReportCategory(
      id: 'violence',
      label: 'Violence',
      description: 'Physical threats, promoting violence',
      icon: 'flame',
    ),
    'illegal_activity': ReportCategory(
      id: 'illegal_activity',
      label: 'Illegal Activity',
      description: 'Prohibited items or services',
      icon: 'shield',
    ),
    'other': ReportCategory(
      id: 'other',
      label: 'Other',
      description: 'Not covered above',
      icon: 'ellipsis',
    ),
  };

  // ── Product report categories (from product detail) ─────────
  static const Map<String, ReportCategory> productCategories = {
    'counterfeit': ReportCategory(
      id: 'counterfeit',
      label: 'Counterfeit / Fake Item',
      description: 'Item is not genuine or is a knockoff',
      icon: 'shieldOff',
    ),
    'misleading_listing': ReportCategory(
      id: 'misleading_listing',
      label: 'Misleading Listing',
      description: 'Description, photos, or price don\'t match reality',
      icon: 'eyeOff',
    ),
    'prohibited_item': ReportCategory(
      id: 'prohibited_item',
      label: 'Prohibited Item',
      description: 'Item violates campus or marketplace rules',
      icon: 'ban',
    ),
    'product_scam': ReportCategory(
      id: 'product_scam',
      label: 'Scam / Fraud',
      description: 'Seller is attempting to defraud buyers',
      icon: 'circleAlert',
    ),
    'stolen_property': ReportCategory(
      id: 'stolen_property',
      label: 'Stolen Property',
      description: 'Item may be stolen',
      icon: 'lock',
    ),
    'price_gouging': ReportCategory(
      id: 'price_gouging',
      label: 'Price Gouging',
      description: 'Excessively inflated pricing',
      icon: 'trendingUp',
    ),
    'other': ReportCategory(
      id: 'other',
      label: 'Other',
      description: 'Not covered above',
      icon: 'ellipsis',
    ),
  };

  /// Submit a report against a user (from chat)
  static Future<void> submitReport({
    required String reportedUserId,
    required String category,
    String? description,
    String? conversationId,
  }) async {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    await SupabaseService.client.from('reports').insert({
      'reporter_id': uid,
      'reported_user_id': reportedUserId,
      'category': category,
      'description': description?.trim().isNotEmpty == true
          ? description!.trim()
          : null,
      'conversation_id': conversationId,
    });
  }

  /// Submit a user complaint (for suspended users)
  static Future<void> submitComplaint({
    required String userId,
    required String complaintText,
    String? reportId,
  }) async {
    await SupabaseService.client.from('user_complaints').insert({
      'user_id': userId,
      'complaint_text': complaintText.trim(),
      'report_id': reportId,
    });
  }

  /// Submit a report against a product/listing
  static Future<void> submitProductReport({
    required String productId,
    required String reportedUserId,
    required String category,
    String? description,
    required String productTitle,
    required String reporterEmail,
    required String reporterName,
  }) async {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    await SupabaseService.client.from('reports').insert({
      'reporter_id': uid,
      'reported_user_id': reportedUserId,
      'product_id': productId,
      'category': category,
      'description': description?.trim().isNotEmpty == true
          ? description!.trim()
          : null,
    });

    // Send confirmation email to reporter
    final categoryLabel = productCategories[category]?.label ?? category;
    await EmailService.sendProductReportConfirmation(
      reporterEmail: reporterEmail,
      reporterName: reporterName,
      productTitle: productTitle,
      category: categoryLabel,
    );

    // Send admin notification email
    try {
      final adminData = await SupabaseService.client
          .from('users')
          .select('email')
          .eq('is_admin', true)
          .limit(1)
          .maybeSingle();
      if (adminData != null) {
        await EmailService.sendAdminProductReportNotification(
          adminEmail: adminData['email'] as String,
          productTitle: productTitle,
          reporterName: reporterName,
          category: categoryLabel,
          description: description,
          productId: productId,
        );
      }
    } catch (_) {
      // Non-critical — don't fail the report if admin email fails
    }
  }

  /// Submit a report against a service listing, optionally with evidence
  /// image URLs (already uploaded to R2).
  static Future<void> submitServiceReport({
    required String serviceId,
    required String reportedUserId,
    required String category,
    String? description,
    List<String> evidenceUrls = const [],
    required String serviceTitle,
    required String reporterEmail,
    required String reporterName,
  }) async {
    final uid = SupabaseService.auth.currentUser?.id;
    if (uid == null) throw Exception('Not authenticated');

    await SupabaseService.client.from('reports').insert({
      'reporter_id': uid,
      'reported_user_id': reportedUserId,
      'service_id': serviceId,
      'category': category,
      'description': description?.trim().isNotEmpty == true
          ? description!.trim()
          : null,
      'media_urls': evidenceUrls,
    });

    // Send confirmation email to reporter (reuses the product template).
    final categoryLabel = serviceCategories[category]?.label ?? category;
    await EmailService.sendProductReportConfirmation(
      reporterEmail: reporterEmail,
      reporterName: reporterName,
      productTitle: serviceTitle,
      category: categoryLabel,
    );

    // Send admin notification email
    try {
      final adminData = await SupabaseService.client
          .from('users')
          .select('email')
          .eq('is_admin', true)
          .limit(1)
          .maybeSingle();
      if (adminData != null) {
        await EmailService.sendAdminProductReportNotification(
          adminEmail: adminData['email'] as String,
          productTitle: serviceTitle,
          reporterName: reporterName,
          category: categoryLabel,
          description: description,
          productId: serviceId,
        );
      }
    } catch (_) {
      // Non-critical — don't fail the report if admin email fails
    }
  }

  /// Submit a complaint/appeal when a service provider account has been disabled
  static Future<void> submitServiceProviderAppeal({
    required String complaintText,
  }) async {
    final user = SupabaseService.auth.currentUser;
    if (user == null) throw Exception('Not authenticated');

    final profile = await AuthService.getCurrentUserProfile();
    final userEmail = profile?.email ?? user.email ?? '';
    final userName = profile?.fullName ?? 'User';
    final userUniversity = profile?.university ?? 'Unknown';

    // 1. Insert into reports table (so it appears on the Admin Reports dashboard)
    final reportRes = await SupabaseService.client
        .from('reports')
        .insert({
          'reporter_id': user.id,
          'reported_user_id': user.id,
          'category': 'service_provider_appeal',
          'description': complaintText.trim(),
          'status': 'pending',
          'is_read': false,
          'media_urls': <String>[],
        })
        .select('id')
        .single();

    final reportId = reportRes['id'] as String;

    // 2. Insert into user_complaints table
    await SupabaseService.client.from('user_complaints').insert({
      'user_id': user.id,
      'report_id': reportId,
      'complaint_text': complaintText.trim(),
      'status': 'pending',
    });

    // 3. Send confirmation email to the user
    if (userEmail.isNotEmpty) {
      await EmailService.sendServiceProviderComplaintConfirmation(
        userEmail: userEmail,
        userName: userName,
        complaintText: complaintText.trim(),
      );
    }

    // 4. Send notification email to the admin
    try {
      final adminData = await SupabaseService.client
          .from('users')
          .select('email')
          .eq('is_admin', true)
          .limit(1)
          .maybeSingle();
      if (adminData != null && adminData['email'] != null) {
        await EmailService.sendAdminServiceProviderComplaintNotification(
          adminEmail: adminData['email'] as String,
          userName: userName,
          userEmail: userEmail,
          userUniversity: userUniversity,
          complaintText: complaintText.trim(),
          userId: user.id,
        );
      }
    } catch (_) {
      // Non-critical — don't fail the complaint submission if admin email lookup fails
    }
  }

  /// Get the user's latest service provider appeal / complaint
  static Future<Map<String, dynamic>?> getLatestServiceProviderAppeal() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return null;
    try {
      final report = await SupabaseService.client
          .from('reports')
          .select('id, description, status, admin_notes, created_at')
          .eq('reporter_id', userId)
          .eq('category', 'service_provider_appeal')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (report == null) return null;

      // Extract the complaint text from user_complaints or description
      String? complaintText;
      try {
        final complaint = await SupabaseService.client
            .from('user_complaints')
            .select('complaint_text')
            .eq('report_id', report['id'])
            .maybeSingle();
        complaintText = complaint?['complaint_text'] as String?;
      } catch (_) {}

      complaintText ??= report['description'] as String?;

      return {
        'id': report['id'],
        'complaint_text': complaintText,
        'status': report['status'],
        'admin_notes': report['admin_notes'],
        'created_at': report['created_at'],
      };
    } catch (_) {
      return null;
    }
  }

  /// Categories used by the service report screen.
  static const Map<String, ReportCategory> serviceCategories = {
    'misleading_service': ReportCategory(
      id: 'misleading_service',
      label: 'Misleading Service',
      description: 'The service doesn\'t match its description or gallery',
      icon: 'file_question',
    ),
    'service_scam': ReportCategory(
      id: 'service_scam',
      label: 'Scam or Fraud',
      description: 'This service is trying to scam customers',
      icon: 'shield_alert',
    ),
    'spam': ReportCategory(
      id: 'spam',
      label: 'Spam',
      description: 'Repeated or unwanted listing',
      icon: 'ban',
    ),
    'inappropriate_content': ReportCategory(
      id: 'inappropriate_content',
      label: 'Inappropriate Content',
      description: 'Contains offensive or inappropriate material',
      icon: 'eye_off',
    ),
    'price_gouging': ReportCategory(
      id: 'price_gouging',
      label: 'Unfair Pricing',
      description: 'Exploitative or unreasonable pricing',
      icon: 'trending_up',
    ),
    'other': ReportCategory(
      id: 'other',
      label: 'Other',
      description: 'Something else not covered above',
      icon: 'help_circle',
    ),
  };
}

class ReportCategory {
  final String id;
  final String label;
  final String description;
  final String icon;

  const ReportCategory({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
  });
}
