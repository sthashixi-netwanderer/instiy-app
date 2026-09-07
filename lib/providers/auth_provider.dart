import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/chat_media_cache_service.dart';
import '../services/local_notification_service.dart';
import '../services/navigation_service.dart';
import '../services/secrets_service.dart';
import '../services/supabase_service.dart';
import 'account_status_provider.dart';

class AuthProvider extends ChangeNotifier {
  final Ref _ref;
  AppUser? _user;
  bool _isLoading = false;
  String? _error;
  RealtimeChannel? _verificationChannel;
  bool _isSuspended = false;

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSuspended => _isSuspended;

  bool get isAuthenticated => _user != null && !_isSuspended;

  AuthProvider(this._ref) {
    // Realtime suspension/reinstatement is owned by AccountStatusNotifier;
    // mirror its flag here so splash/login gating stays in sync.
    _ref.listen(accountStatusProvider, (previous, next) {
      if (next != _isSuspended) {
        _isSuspended = next;
        _error = null;
        notifyListeners();
      }
    });
    _init();
  }

  /// Point the account-status watcher at the current user (or stop it when
  /// signed out). Idempotent — safe to call from every auth path.
  void _syncAccountStatus() {
    _ref.read(accountStatusProvider.notifier).watchUser(
          _user?.id,
          suspended: _user?.suspended ?? false,
        );
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
              _syncAccountStatus();
              _subscribeToVerificationChanges();
              _error = null;
              _isLoading = false;
              unawaited(SecretsService.instance.initialize());
              notifyListeners();
            } else {
              // Existing Google user — login flow
              _user = await AuthService.getCurrentUserProfile();
              _syncAccountStatus();
              _subscribeToVerificationChanges();
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
      _syncAccountStatus();

      // Ensure user email is bound and synced with auth account
      if (_user != null && _user!.email.isEmpty) {
        final authEmail = SupabaseService.instance.currentUser?.email;
        if (authEmail != null && authEmail.isNotEmpty) {
          _user = _user!.copyWith(email: authEmail);
          try {
            await SupabaseService.table('users').update({'email': authEmail}).eq('id', _user!.id);
          } catch (_) {}
        }
      }

      // Check if user is suspended
      if (_user != null && _user!.suspended) {
        _isSuspended = true;
        _isLoading = false;
        notifyListeners();
        return;
      }

      _isSuspended = false;
      _subscribeToVerificationChanges();
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

  /// Realtime suspension detection lives in AccountStatusNotifier
  /// (accountStatusProvider), which navigates globally when the admin flips
  /// `users.suspended` and reloads the profile on reinstatement.

  /// Re-fetch the current user's profile after the admin reinstates the
  /// account, and resync the realtime watcher. Mirrors `loadUserProfile` but
  /// skips the loading spinner / verification-subscription churn so the
  /// bounce-back to /home feels instant.
  Future<void> refreshOnReinstate() async {
    try {
      _user = await AuthService.getCurrentUserProfile();
      _syncAccountStatus();
      _subscribeToVerificationChanges();
    } catch (_) {
      // Fall through; the watcher is already in the correct state and the
      // next profile load will recover.
    }
  }

  /// Called on app resume to re-check suspension from the database.
  /// Catches cases where Realtime missed the update (app was backgrounded, network issues).
  Future<void> checkSuspensionOnResume() async {
    if (_user == null || _isSuspended) return;

    try {
      final profile = await AuthService.getCurrentUserProfile();
      if (profile != null && profile.suspended && !_isSuspended) {
        _ref.read(accountStatusProvider.notifier).markSuspended();
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
    String? referralCode,
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
        referralCode: referralCode,
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
      _syncAccountStatus();
      _subscribeToVerificationChanges();
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
    _isSuspended = false;
    // Drop session-cached chat images so the next login re-fetches them
    // from R2 on demand instead of serving another account's copies.
    unawaited(ChatMediaCacheManager().emptyCache());
    await AuthService.signOut();
    _user = null;
    _syncAccountStatus();
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
    super.dispose();
  }
}
