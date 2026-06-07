import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/seller_verification_model.dart';
import 'storage_service.dart';
import 'local_notification_service.dart';
import 'email_service.dart';

class VerificationService {
  static final _supabase = Supabase.instance.client;

  /// Fetch the current user's verification records
  static Future<List<SellerVerification>> getMyVerifications() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final data = await _supabase
        .from('seller_verifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => SellerVerification.fromJson(json))
        .toList();
  }

  /// Fetch the latest verification for the current user
  static Future<SellerVerification?> getLatestVerification() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final data = await _supabase
        .from('seller_verifications')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (data == null) return null;
    return SellerVerification.fromJson(data);
  }

  /// Submit a verification request
  /// Returns the created SellerVerification record
  static Future<SellerVerification> submitVerification({
    required DateTime dateOfBirth,
    required int yearOfEntrance,
    required int graduationYear,
    required String residentialAddress,
    String? digitalAddress,
    required File studentIdFront,
    required File studentIdBack,
    required File liveVideo,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    // Check for existing pending verification
    final existing = await _supabase
        .from('seller_verifications')
        .select('id')
        .eq('user_id', userId)
        .eq('status', 'pending')
        .maybeSingle();

    if (existing != null) {
      throw Exception('You already have a pending verification request');
    }

    // Upload media files to R2 in parallel
    final futures = await Future.wait([
      StorageService.uploadFile(
        file: studentIdFront,
        folder: 'verifications/student-ids',
        contentType: 'image/jpeg',
        extension: 'jpg',
      ),
      StorageService.uploadFile(
        file: studentIdBack,
        folder: 'verifications/student-ids',
        contentType: 'image/jpeg',
        extension: 'jpg',
      ),
      StorageService.uploadFile(
        file: liveVideo,
        folder: 'verifications/videos',
        contentType: 'video/mp4',
        extension: 'mp4',
      ),
    ]);

    final frontUrl = futures[0];
    final backUrl = futures[1];
    final videoUrl = futures[2];

    // Insert verification record
    final data = await _supabase
        .from('seller_verifications')
        .insert({
          'user_id': userId,
          'date_of_birth': dateOfBirth.toIso8601String().split('T')[0],
          'year_of_entrance': yearOfEntrance,
          'graduation_year': graduationYear,
          'residential_address': residentialAddress,
          'digital_address': digitalAddress,
          'student_id_front_url': frontUrl,
          'student_id_back_url': backUrl,
          'live_video_url': videoUrl,
          'status': 'pending',
        })
        .select()
        .single();

    return SellerVerification.fromJson(data);
  }

  /// Cancel a pending verification request (user action)
  static Future<void> cancelVerification(String verificationId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    await _supabase
        .from('seller_verifications')
        .update({'status': 'cancelled'})
        .eq('id', verificationId)
        .eq('user_id', userId)
        .eq('status', 'pending');
  }

  /// Admin: Fetch all verification requests with user info
  static Future<List<Map<String, dynamic>>> getVerificationsForAdmin({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _supabase
        .from('seller_verifications')
        .select('*, users:user_id(id, full_name, email, avatar_url, university, is_verified)');

    if (status != null && status.isNotEmpty) {
      query = query.eq('status', status);
    }

    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return List<Map<String, dynamic>>.from(data);
  }

  /// Admin: Approve a verification
  static Future<Map<String, dynamic>> approveVerification({
    required String verificationId,
    String? notes,
  }) async {
    final data = await _supabase.rpc('approve_seller_verification', params: {
      'p_verification_id': verificationId,
      'p_admin_id': _supabase.auth.currentUser?.id,
      'p_notes': notes,
    });

    // Send email and notification
    if (data is Map && data['success'] == true) {
      final userId = data['user_id'] as String?;
      if (userId != null) {
        final user = await _supabase
            .from('users')
            .select('full_name, email')
            .eq('id', userId)
            .maybeSingle();

        if (user != null) {
          final email = user['email'] as String?;
          final name = user['full_name'] as String? ?? 'Seller';
          await LocalNotificationService.notifyVerificationApproved();
          if (email != null) {
            await EmailService.sendVerificationApproved(
              userEmail: email,
              userName: name,
            );
          }
        }
      }
    }

    return Map<String, dynamic>.from(data);
  }

  /// Admin: Reject a verification
  static Future<Map<String, dynamic>> rejectVerification({
    required String verificationId,
    String? notes,
  }) async {
    final data = await _supabase.rpc('reject_seller_verification', params: {
      'p_verification_id': verificationId,
      'p_admin_id': _supabase.auth.currentUser?.id,
      'p_notes': notes,
    });

    // Send email and notification
    if (data is Map && data['success'] == true) {
      // Get user info from verification record
      final verification = await _supabase
          .from('seller_verifications')
          .select('user_id')
          .eq('id', verificationId)
          .maybeSingle();

      if (verification != null) {
        final user = await _supabase
            .from('users')
            .select('full_name, email')
            .eq('id', verification['user_id'])
            .maybeSingle();

        if (user != null) {
          final email = user['email'] as String?;
          final name = user['full_name'] as String? ?? 'Seller';
          await LocalNotificationService.notifyVerificationRejected(reason: notes);
          if (email != null) {
            await EmailService.sendVerificationRejected(
              userEmail: email,
              userName: name,
              reason: notes,
            );
          }
        }
      }
    }

    return Map<String, dynamic>.from(data);
  }

  /// Admin: Revoke a previously approved verification
  static Future<Map<String, dynamic>> revokeVerification({
    required String verificationId,
    String? notes,
  }) async {
    final data = await _supabase.rpc('revoke_seller_verification', params: {
      'p_verification_id': verificationId,
      'p_admin_id': _supabase.auth.currentUser?.id,
      'p_notes': notes,
    });
    return Map<String, dynamic>.from(data);
  }
}
