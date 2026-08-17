import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/seller_verification_model.dart';
import '../services/verification_service.dart';
import '../services/supabase_service.dart';

class VerificationProvider extends ChangeNotifier {
  SellerVerification? _latestVerification;
  bool _isLoading = false;
  bool _isSubmitting = false;
  bool _isUploadingBackground = false;
  String? _error;

  /// Called when a verification transitions to 'approved' or when
  /// `is_verified` is set to true directly by admin.
  VoidCallback? onVerificationApproved;

  /// Called when `is_verified` is revoked (set to false) by admin.
  VoidCallback? onVerificationRevoked;

  RealtimeChannel? _verificationChannel;
  RealtimeChannel? _usersChannel;
  String? _currentUserId;

  VerificationProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        final userId = session.user.id;
        if (_currentUserId == userId) return;
        _currentUserId = userId;
        _subscribeToRealtime(userId);
      } else {
        _unsubscribeFromRealtime();
        _latestVerification = null;
        _currentUserId = null;
        _error = null;
        notifyListeners();
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      _subscribeToRealtime(currentUser.id);
    }
  }

  void _subscribeToRealtime(String userId) {
    _unsubscribeFromRealtime();

    // Listen to seller_verifications for status changes (pending → approved/rejected)
    _verificationChannel = SupabaseService.client
        .channel('user-verifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'seller_verifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            _silentReload();
          },
        );
    _verificationChannel!.subscribe();

    // Also listen to the users table so that when admin directly toggles
    // is_verified (without going through seller_verifications), the
    // verification screen and badges update immediately.
    _usersChannel = SupabaseService.client
        .channel('user-is-verified:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) {
            final newRecord = payload.newRecord;
            final isVerified = newRecord['is_verified'] as bool? ?? false;
            if (isVerified) {
              onVerificationApproved?.call();
            } else {
              onVerificationRevoked?.call();
            }
            // Also reload seller_verifications so the screen reflects any
            // status change that may have been made alongside the toggle.
            _silentReload();
          },
        );
    _usersChannel!.subscribe();

    loadLatestVerification();
  }

  void _unsubscribeFromRealtime() {
    if (_verificationChannel != null) {
      SupabaseService.client.removeChannel(_verificationChannel!);
      _verificationChannel = null;
    }
    if (_usersChannel != null) {
      SupabaseService.client.removeChannel(_usersChannel!);
      _usersChannel = null;
    }
  }

  Future<void> _silentReload() async {
    try {
      final previous = _latestVerification;
      final verification = await VerificationService.getLatestVerification();
      _latestVerification = verification;
      notifyListeners();

      final wasApproved = previous != null && previous.isApproved;
      final isNowApproved = verification != null && verification.isApproved;

      // Just became approved → update badge everywhere
      if (!wasApproved && isNowApproved) {
        onVerificationApproved?.call();
      }

      // Was approved but now revoked/rejected → remove badge everywhere
      if (wasApproved && !isNowApproved) {
        onVerificationRevoked?.call();
      }
    } catch (_) {}
  }

  SellerVerification? get latestVerification => _latestVerification;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  bool get isUploadingBackground => _isUploadingBackground;
  String? get error => _error;

  void setUploadingBackground(bool val) {
    _isUploadingBackground = val;
    notifyListeners();
  }

  Future<void> loadLatestVerification() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final verification = await VerificationService.getLatestVerification();
      _latestVerification = verification;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> submitVerification({
    required DateTime dateOfBirth,
    required int yearOfEntrance,
    required int graduationYear,
    required String residentialAddress,
    String? digitalAddress,
    required File studentIdFront,
    required File studentIdBack,
    required File liveVideo,
  }) async {
    _isSubmitting = true;
    _error = null;
    notifyListeners();

    try {
      final verification = await VerificationService.submitVerification(
        dateOfBirth: dateOfBirth,
        yearOfEntrance: yearOfEntrance,
        graduationYear: graduationYear,
        residentialAddress: residentialAddress,
        digitalAddress: digitalAddress,
        studentIdFront: studentIdFront,
        studentIdBack: studentIdBack,
        liveVideo: liveVideo,
      );
      _latestVerification = verification;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> submitVerificationInBackground({
    required DateTime dateOfBirth,
    required int yearOfEntrance,
    required int graduationYear,
    required String residentialAddress,
    String? digitalAddress,
    required File studentIdFront,
    required File studentIdBack,
    required File liveVideo,
  }) async {
    _isUploadingBackground = true;
    _error = null;
    notifyListeners();

    try {
      final verification = await VerificationService.submitVerification(
        dateOfBirth: dateOfBirth,
        yearOfEntrance: yearOfEntrance,
        graduationYear: graduationYear,
        residentialAddress: residentialAddress,
        digitalAddress: digitalAddress,
        studentIdFront: studentIdFront,
        studentIdBack: studentIdBack,
        liveVideo: liveVideo,
      );
      _latestVerification = verification;
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isUploadingBackground = false;
      notifyListeners();
    }
  }

  Future<void> cancelVerification(String verificationId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await VerificationService.cancelVerification(verificationId);
      await loadLatestVerification();
    } catch (e) {
      _error = e.toString();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
