import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import 'supabase_service.dart';
import 'secrets_service.dart';

class AuthService {
  static User? get currentUser => SupabaseService.auth.currentUser;
  
  static bool get isAuthenticated => currentUser != null;
  
  static Stream<AuthState> get authStateChanges => 
      SupabaseService.auth.onAuthStateChange;

  static final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  /// Initialize Google Sign-In. Call once at app startup.
  static Future<void> initializeGoogleSignIn() async {
    await _googleSignIn.initialize(
      // On Android, the web client ID is read from google-services.json.
      // On iOS, the client ID is read from Info.plist (GIDClientID).
      // We pass serverClientId as fallback for Android.
      serverClientId: kIsWeb ? null : '658847293429-2f0sb9nbvrkak2dp9ni87l5pk85ke1tq.apps.googleusercontent.com',
    );
  }
  
  // Sign up with email and password
  static Future<AppUser> signUp({
    required String email,
    required String password,
    required String fullName,
    required String walletTag,
    String? university,
    String? phoneNumber,
  }) async {
    final response = await SupabaseService.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'wallet_tag': walletTag,
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
  
  // Sign in with Google (native SDK on Android/iOS, OAuth redirect on web)
  static Future<bool> signInWithGoogle() async {
    if (kIsWeb) {
      // Web: use Supabase OAuth redirect flow (unchanged)
      return await SupabaseService.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SecretsService.instance.supabaseRedirectUrl,
        authScreenLaunchMode: LaunchMode.inAppWebView,
      );
    }

    // Android & iOS: use native Google Sign-In SDK
    final account = await _googleSignIn.authenticate();

    final GoogleSignInAuthentication auth = account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) return false;

    // Exchange Google ID token with Supabase
    final response = await SupabaseService.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );

    return response.session != null;
  }
  
  // Sign out
  static Future<void> signOut() async {
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
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

  // Get user profile by ID
  static Future<AppUser?> getUserProfileById(String id) async {
    try {
      final userProfile = await SupabaseService.table('users')
          .select()
          .eq('id', id)
          .maybeSingle();
      if (userProfile == null) return null;
      return AppUser.fromJson(userProfile);
    } catch (_) {
      return null;
    }
  }

  // Check if a wallet tag already exists in the users table
  static Future<bool> checkWalletTagExists(String tag) async {
    try {
      final response = await SupabaseService.table('users')
          .select('id')
          .eq('wallet_tag', tag.toLowerCase().trim())
          .maybeSingle();
      return response != null;
    } catch (_) {
      return false;
    }
  }

  // Generate 5 recommended tags based on first and last name plus random digits
  static Future<List<String>> generateRecommendedTags(String fullName) async {
    final parts = fullName.split(RegExp(r'\s+'));
    final firstName = parts.isNotEmpty ? parts.first.toLowerCase() : '';
    final lastName = parts.length > 1 ? parts.last.toLowerCase() : '';

    final cleanFirst = firstName.replaceAll(RegExp(r'[^a-zA-Z]'), '');
    final cleanLast = lastName.replaceAll(RegExp(r'[^a-zA-Z]'), '');

    String padName(String name) {
      if (name.length >= 5) return name;
      return name.padRight(5, 'x');
    }

    final baseFirst = padName(cleanFirst.isNotEmpty ? cleanFirst : 'user');
    final baseLast = padName(cleanLast.isNotEmpty ? cleanLast : 'tag');

    final rand = Random();
    final List<String> candidates = [];

    // Pattern 1: {cleanFirst}{digits}
    // Pattern 2: {cleanLast}{digits}
    // Pattern 3: {digit}{cleanFirst}{digits}
    // Pattern 4: {digit}{cleanLast}{digits}
    // Pattern 5: {cleanFirst}{cleanLast}{digits}
    for (int i = 0; i < 4; i++) {
      candidates.add('$baseFirst${rand.nextInt(90) + 10}');
      candidates.add('$baseLast${rand.nextInt(900) + 100}');
      candidates.add('${rand.nextInt(9) + 1}$baseFirst${rand.nextInt(90) + 10}');
      candidates.add('${rand.nextInt(9) + 1}$baseLast${rand.nextInt(90) + 10}');
      candidates.add('$baseFirst$baseLast${rand.nextInt(9) + 1}');
    }

    final uniqueCandidates = candidates.toSet().toList();

    try {
      final response = await SupabaseService.client
          .from('users')
          .select('wallet_tag')
          .inFilter('wallet_tag', uniqueCandidates);

      final takenTags = (response as List)
          .map((row) => (row['wallet_tag'] as String).toLowerCase())
          .toSet();

      final List<String> available = [];
      for (final cand in uniqueCandidates) {
        if (!takenTags.contains(cand.toLowerCase())) {
          available.add(cand);
          if (available.length >= 5) break;
        }
      }

      while (available.length < 5) {
        final fallback = '$baseFirst${rand.nextInt(9000) + 1000}';
        if (!available.contains(fallback)) {
          available.add(fallback);
        }
      }

      return available;
    } catch (_) {
      return uniqueCandidates.take(5).toList();
    }
  }
}
