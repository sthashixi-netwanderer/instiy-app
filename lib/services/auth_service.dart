import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'supabase_service.dart';
import 'secrets_service.dart';

class AuthService {
  static User? get currentUser => SupabaseService.auth.currentUser;
  
  static bool get isAuthenticated => currentUser != null;
  
  static Stream<AuthState> get authStateChanges => 
      SupabaseService.auth.onAuthStateChange;
  
  // Sign up with email and password
  static Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
    String? university,
    String? phoneNumber,
  }) async {
    final response = await SupabaseService.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'university': university,
        'phone_number': phoneNumber,
      },
    );
    
    if (response.user == null) {
      throw Exception('Failed to create account');
    }
    
    // User profile is automatically created by the handle_new_user() trigger
    // Fetch the profile that was created by the trigger
    final userProfile = await SupabaseService.table('users')
        .select()
        .eq('id', response.user!.id)
        .single();
    
    return AppUser.fromJson(userProfile);
  }
  
  // Sign in with email and password
  static Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    final response = await SupabaseService.auth.signInWithPassword(
      email: email,
      password: password,
    );
    
    if (response.user == null) {
      throw Exception('Failed to sign in');
    }
    
    // Fetch user profile
    final userProfile = await SupabaseService.table('users')
        .select()
        .eq('id', response.user!.id)
        .single();
    
    return AppUser.fromJson(userProfile);
  }
  
  // Sign in with Google
  static Future<bool> signInWithGoogle() async {
    return await SupabaseService.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? SecretsService.instance.supabaseRedirectUrl : 'io.supabase.instiy://login-callback',
      authScreenLaunchMode: LaunchMode.inAppWebView,
    );
  }
  
  // Sign out
  static Future<void> signOut() async {
    await SupabaseService.auth.signOut();
  }
  
  // Get current user profile
  static Future<AppUser?> getCurrentUserProfile() async {
    if (!isAuthenticated) return null;
    
    try {
      final userProfile = await SupabaseService.table('users')
          .select()
          .eq('id', currentUser!.id)
          .single();
      
      return AppUser.fromJson(userProfile);
    } catch (e) {
      return null;
    }
  }
  
  // Update user profile
  static const _sentinel = Object();

  static Future<AppUser> updateProfile({
    String? fullName,
    String? university,
    String? bio,
    String? phoneNumber,
    Object? avatarUrl = _sentinel,
  }) async {
    if (!isAuthenticated) throw Exception('Not authenticated');

    final updates = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };

    if (fullName != null) updates['full_name'] = fullName;
    if (university != null) updates['university'] = university;
    if (bio != null) updates['bio'] = bio;
    if (phoneNumber != null) updates['phone_number'] = phoneNumber;
    if (avatarUrl != _sentinel) updates['avatar_url'] = avatarUrl;

    await SupabaseService.table('users')
        .update(updates)
        .eq('id', currentUser!.id);

    final updatedProfile = await SupabaseService.table('users')
        .select()
        .eq('id', currentUser!.id)
        .single();

    return AppUser.fromJson(updatedProfile);
  }
  
  // Reset password
  static Future<void> resetPassword(String email) async {
    await SupabaseService.auth.resetPasswordForEmail(
      email,
      redirectTo: kIsWeb ? SecretsService.instance.supabaseRedirectUrl : 'io.supabase.instiy://login-callback',
    );
  }

  // Toggle seller verification status
  static Future<bool> toggleVerification() async {
    if (!isAuthenticated) throw Exception('Not authenticated');
    final uid = currentUser!.id;

    final current = await SupabaseService.table('users')
        .select('is_verified')
        .eq('id', uid)
        .single();

    final newStatus = !((current['is_verified'] as bool?) ?? false);

    await SupabaseService.table('users')
        .update({'is_verified': newStatus, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', uid);

    return newStatus;
  }

  // Check if an email already exists in the users table
  static Future<bool> checkEmailExists(String email) async {
    try {
      final response = await SupabaseService.table('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }

  // Check if a phone number already exists in the users table
  static Future<bool> checkPhoneExists(String phone) async {
    try {
      final response = await SupabaseService.table('users')
          .select('id')
          .eq('phone_number', phone)
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }

  /// Checks if a phone number is already taken by any user across
  /// both `users.phone_number` and `business_profiles.phone_numbers`.
  /// Normalizes a phone number string to E.164 format (+233XXXXXXXXX).
  /// Returns null if the input cannot be normalized to a valid number.
  static String? _normalizeToE164(String phone) {
    final digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return null;

    String e164;
    if (digits.startsWith('233') && digits.length == 12) {
      // Already has country code: 233XXXXXXXXX → +233XXXXXXXXX
      e164 = '+$digits';
    } else if (digits.startsWith('0') && digits.length == 10) {
      // Local format: 0XXXXXXXXX → +233XXXXXXXXX
      e164 = '+233${digits.substring(1)}';
    } else if (digits.length == 9) {
      // Raw number without leading zero: XXXXXXXXX → +233XXXXXXXXX
      e164 = '+233$digits';
    } else {
      return null; // Unrecognized format
    }

    // Validate: Ghana mobile numbers are 9 digits after country code
    final localPart = e164.substring(4); // Remove +233
    if (localPart.length != 9) return null;

    return e164;
  }

  /// Checks if a phone number is already taken by another user.
  /// Normalizes both the input and stored numbers before comparing.
  /// Pass [excludeUserId] to skip the current user's own record.
  static Future<bool> isPhoneTaken(String phone, {String? excludeUserId}) async {
    final cleaned = _normalizeToE164(phone);
    if (cleaned == null) return false; // Invalid format, can't be taken

    // Also build a local-format variant (0XXXXXXXXX) for matching stored raw numbers
    final localFormat = '0${cleaned.substring(4)}';

    // 1. Check users.phone_number (E.164 format)
    try {
      var query = SupabaseService.table('users').select('id').eq('phone_number', cleaned);
      if (excludeUserId != null) {
        query = query.neq('id', excludeUserId);
      }
      final match = await query.maybeSingle();
      if (match != null) return true;
    } catch (_) {}

    // 2. Check users.phone_number (local format)
    try {
      var query = SupabaseService.table('users').select('id').eq('phone_number', localFormat);
      if (excludeUserId != null) {
        query = query.neq('id', excludeUserId);
      }
      final match = await query.maybeSingle();
      if (match != null) return true;
    } catch (_) {}

    // 3. Check business_profiles.phone_numbers (JSONB array)
    try {
      var query = SupabaseService.table('business_profiles').select('seller_id, phone_numbers');
      if (excludeUserId != null) {
        query = query.neq('seller_id', excludeUserId);
      }
      final profiles = await query;

      for (final profile in profiles) {
        final phones = profile['phone_numbers'] as List? ?? [];
        for (final phoneEntry in phones) {
          if (phoneEntry is! Map) continue;
          final stored = (phoneEntry['number'] as String?) ?? '';
          if (stored.isEmpty) continue;

          final normalizedStored = _normalizeToE164(stored);
          if (normalizedStored == cleaned) return true;
        }
      }
    } catch (_) {}

    return false;
  }

  // Get user profile by email
  static Future<AppUser?> getUserProfileByEmail(String email) async {
    try {
      final userProfile = await SupabaseService.table('users')
          .select()
          .eq('email', email)
          .maybeSingle();
      if (userProfile == null) return null;
      return AppUser.fromJson(userProfile);
    } catch (_) {
      return null;
    }
  }
}
