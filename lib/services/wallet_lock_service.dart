import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalletLockService {
  static const _lockEnabledKey = 'wallet_lock_enabled';
  static final _localAuth = LocalAuthentication();

  /// Whether wallet lock is enabled
  static Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lockEnabledKey) ?? false;
  }

  /// Enable or disable wallet lock
  static Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockEnabledKey, enabled);
  }

  /// Check if the device supports biometric/screen lock
  static Future<bool> isDeviceSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Check if biometrics are available
  static Future<bool> hasBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  /// Authenticate using biometrics or screen lock
  /// Returns true if authentication succeeded
  static Future<bool> authenticate({String? reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason ?? 'Authenticate to access your wallet',
        persistAcrossBackgrounding: true,
        biometricOnly: false,
      );
    } catch (_) {
      return false;
    }
  }

  /// If lock is enabled, prompt authentication.
  /// Returns true if lock is disabled OR authentication succeeded.
  /// Returns false if lock is enabled and authentication failed/cancelled.
  static Future<bool> unlockIfNeeded({String? reason}) async {
    final enabled = await isLockEnabled();
    if (!enabled) return true;
    return authenticate(reason: reason);
  }
}
