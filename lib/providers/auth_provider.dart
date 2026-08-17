import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/local_notification_service.dart';
import '../services/navigation_service.dart';
import '../services/secrets_service.dart';
import '../services/supabase_service.dart';

class AuthProvider extends ChangeNotifier {
  AppUser? _user;
  bool _isLoading = false;
  String? _error;
  RealtimeChannel? _verificationChannel;
  RealtimeChannel? _suspensionChannel;
  bool _isSuspended = false;

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSuspended => _isSuspended;

  bool get isAuthenticated => _user != null && !_isSuspended;

  AuthProvider() {
    _init();
  }

  Future<void> _init() async {
    // Initialize native Google Sign-In (Android/iOS only)
    if (!kIsWeb) {
      await AuthService.initializeGoogleSignIn();
    }

    // Listen to auth state changes
    AuthService.authStateChanges.listen((state) async {
      final event = state.event;
      final session = state.session;

      if (event == AuthChangeEvent.passwordRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          NavigationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/reset-password',
            (route) => false,
          );
        });
        return;
      }

      if (session != null) {
        final isGoogle = session.user.appMetadata['provider'] == 'google';
        if (isGoogle) {
          final email = session.user.email;

          if (email != null) {
            // Check if user profile exists to determine login vs signup
            final profile = await AuthService.getUserProfileByEmail(email);

            if (profile == null) {
              // New Google user — profile not yet created (signup flow)
              // The handle_new_user() trigger should create it, but if
              // signInWithIdToken was used, the trigger may not fire.
              // Create the profile manually.
              try {
                await SupabaseService.table('users').insert({
                  'id': session.user.id,
                  'email': email,
                  'full_name': session.user.userMetadata?['full_name'] ?? '',
                  'avatar_url': session.user.userMetadata?['avatar_url'],
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                });
              } catch (_) {
                // Profile may already exist (race condition with trigger)
              }
              _user = await AuthService.getCurrentUserProfile();
              _error = null;
              _isLoading = false;
              unawaited(SecretsService.instance.initialize());
              notifyListeners();
            } else {
              // Existing Google user — login flow
              _user = await AuthService.getCurrentUserProfile();
              if (_user != null && _user!.suspended) {
                _isSuspended = true;
                _isLoading = false;
                notifyListeners();
                return;
              }
              _isSuspended = false;
              _error = null;
              _isLoading = false;
              unawaited(SecretsService.instance.initialize());
              notifyListeners();
            }
          }
        } else {
          // Normal email/password session
          if (_user == null) {
            await loadUserProfile();
          }
        }
        LocalNotificationService.checkAndPromptFcmForAuthenticatedUser(); // ignore: unawaited_futures
      } else {
        if (_user != null || event == AuthChangeEvent.signedOut) {
          _user = null;
          notifyListeners();
        }
      }
    });

    // Check if user is already authenticated immediately
    if (AuthService.isAuthenticated) {
      await loadUserProfile();
      LocalNotificationService.checkAndPromptFcmForAuthenticatedUser(); // ignore: unawaited_futures
    }
  }

  Future<void> loadUserProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await AuthService.getCurrentUserProfile();
      _error = null;

      // Check if user is suspended
      if (_user != null && _user!.suspended) {
        _isSuspended = true;
        _isLoading = false;
        notifyListeners();
        return;
      }

      _isSuspended = false;
      _subscribeToVerificationChanges();
      _subscribeToSuspensionChanges();
      unawaited(SecretsService.instance.initialize());
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Subscribe to Realtime changes on the current user's row in `users`.
  /// Detects when `is_verified` is flipped by an admin approval.
  void _subscribeToVerificationChanges() {
    _unsubscribeFromVerification();

    final uid = _user?.id;
    if (uid == null) return;

    _verificationChannel = Supabase.instance.client
        .channel('user-verification:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (_) async {
            // Reload profile to pick up is_verified change
            try {
              final updated = await AuthService.getCurrentUserProfile();
              if (updated != null) {
                _user = updated;
                notifyListeners();
              }
            } catch (_) {}
          },
        )
        .subscribe();
  }

  void _unsubscribeFromVerification() {
    if (_verificationChannel != null) {
      Supabase.instance.client.removeChannel(_verificationChannel!);
      _verificationChannel = null;
    }
  }

  /// Subscribe to Realtime changes to detect when admin suspends this user.
  void _subscribeToSuspensionChanges() {
    _unsubscribeFromSuspension();

    final uid = _user?.id;
    if (uid == null) return;

    _suspensionChannel = Supabase.instance.client
        .channel('user-suspension:$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: uid,
          ),
          callback: (payload) async {
            final newRecord = payload.newRecord;
            if (newRecord['suspended'] == true && !_isSuspended) {
              await _handleSuspension();
            }
          },
        )
        .subscribe();
  }

  void _unsubscribeFromSuspension() {
    if (_suspensionChannel != null) {
      Supabase.instance.client.removeChannel(_suspensionChannel!);
      _suspensionChannel = null;
    }
  }

  /// Central handler for when suspension is detected (via Realtime or lifecycle check).
  /// Navigates to /suspended FIRST, then signs out in the background.
  Future<void> _handleSuspension() async {
    if (_isSuspended) return; // already handled
    _isSuspended = true;
    _error = null;
    notifyListeners();

    // Navigate FIRST — before signOut triggers auth state listener that nulls _user.
    // Using addPostFrameCallback ensures the current frame completes before navigation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NavigationService.navigatorKey.currentState?.pushNamedAndRemoveUntil(
        '/suspended',
        (route) => false,
      );
    });

    // Then sign out in the background to invalidate the Supabase session.
    // The auth state listener will set _user = null, but _isSuspended is already true
    // so isAuthenticated remains false and the suspended screen stays visible.
    await AuthService.signOut();
  }

  /// Called on app resume to re-check suspension from the database.
  /// Catches cases where Realtime missed the update (app was backgrounded, network issues).
  Future<void> checkSuspensionOnResume() async {
    if (_user == null || _isSuspended) return;

    try {
      final profile = await AuthService.getCurrentUserProfile();
      if (profile != null && profile.suspended && !_isSuspended) {
        await _handleSuspension();
      }
    } catch (_) {
      // Non-critical — don't crash on resume check
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String walletTag,
    String? university,
    String? phoneNumber,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await AuthService.signUp(
        email: email,
        password: password,
        fullName: fullName,
        walletTag: walletTag,
        university: university,
        phoneNumber: phoneNumber,
      );
      _isLoading = false;
      // ignore: unawaited_futures
      SecretsService.instance.initialize();
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await AuthService.signIn(email: email, password: password);
      if (_user != null && _user!.suspended) {
        _isSuspended = true;
        _isLoading = false;
        notifyListeners();
        return false;
      }
      _isSuspended = false;
      _error = null;
      _isLoading = false;
      unawaited(SecretsService.instance.initialize());
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    _unsubscribeFromVerification();
    _unsubscribeFromSuspension();
    _isSuspended = false;
    await AuthService.signOut();
    _user = null;
    notifyListeners();
  }

  Future<void> updateProfile({
    String? fullName,
    String? university,
    String? bio,
    String? phoneNumber,
    Object? avatarUrl = const Object(),
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await AuthService.updateProfile(
        fullName: fullName,
        university: university,
        bio: bio,
        phoneNumber: phoneNumber,
        avatarUrl: avatarUrl,
      );
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signInWithGoogle() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await AuthService.signInWithGoogle();
      if (success) {
        unawaited(SecretsService.instance.initialize());
      }
      return success;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> toggleVerification() async {
    try {
      final newStatus = await AuthService.toggleVerification();
      _user = _user?.copyWith(isVerified: newStatus);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _unsubscribeFromVerification();
    _unsubscribeFromSuspension();
    super.dispose();
  }
}
