import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/local_notification_service.dart';
import '../services/navigation_service.dart';
import '../services/secrets_service.dart';

class AuthProvider extends ChangeNotifier {
  AppUser? _user;
  bool _isLoading = false;
  String? _error;
  RealtimeChannel? _verificationChannel;

  AppUser? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get isAuthenticated => _user != null;
  
  AuthProvider() {
    _init();
  }
  
  Future<void> _init() async {
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
          final prefs = await SharedPreferences.getInstance();
          final mode = prefs.getString('google_auth_mode') ?? 'login';
          final email = session.user.email;
          
          if (email != null) {
            final profile = await AuthService.getUserProfileByEmail(email);
            
            if (mode == 'signup') {
              if (profile != null) {
                // Account already exists. Block registration.
                _error = 'Account already exists. Please sign in instead.';
                await AuthService.signOut();
                _user = null;
                _isLoading = false;
                await prefs.remove('google_auth_mode');
                notifyListeners();
                return;
              } else {
                // New sign up, let it proceed
                _user = await AuthService.getCurrentUserProfile();
                _error = null;
                _isLoading = false;
                await prefs.remove('google_auth_mode');
                unawaited(SecretsService.instance.initialize());
                notifyListeners();
              }
            } else {
              // mode == 'login' — let Google login proceed directly
              _user = await AuthService.getCurrentUserProfile();
              _error = null;
              _isLoading = false;
              await prefs.remove('google_auth_mode');
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
        LocalNotificationService.subscribeToNotifications();
        LocalNotificationService.checkAndPromptFcmForAuthenticatedUser();
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
      LocalNotificationService.subscribeToNotifications();
      LocalNotificationService.checkAndPromptFcmForAuthenticatedUser();
    }
  }
  
  Future<void> loadUserProfile() async {
    _isLoading = true;
    notifyListeners();

    try {
      _user = await AuthService.getCurrentUserProfile();
      _error = null;
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
  
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
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
        university: university,
        phoneNumber: phoneNumber,
      );
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
  
  Future<bool> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      _user = await AuthService.signIn(
        email: email,
        password: password,
      );
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
  
  Future<bool> signInWithGoogle({required bool isSignUp}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('google_auth_mode', isSignUp ? 'signup' : 'login');
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
