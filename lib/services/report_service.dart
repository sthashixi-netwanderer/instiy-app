import 'supabase_service.dart';
import 'email_service.dart';

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
