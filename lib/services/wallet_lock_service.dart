import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WalletLockService {
  static const _lockEnabledKey = 'wallet_lock_enabled';
  static const _screenKeys = {
    'wallet': 'lock_wallet',
    'orders': 'lock_orders',
    'checkout': 'lock_checkout',
    'seller_orders': 'lock_seller_orders',
    'seller_dashboard': 'lock_seller_dashboard',
    'messages': 'lock_messages',
  };
  static final _localAuth = LocalAuthentication();

  /// Whether global app lock is enabled
  static Future<bool> isLockEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_lockEnabledKey) ?? false;
  }

  /// Enable or disable global lock. When enabling, enables all screens.
  /// When disabling, disables all screens.
  static Future<void> setLockEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_lockEnabledKey, enabled);
    for (final key in _screenKeys.values) {
      await prefs.setBool(key, enabled);
    }
  }

  /// Whether a specific screen is locked
  static Future<bool> isScreenLockEnabled(String screenKey) async {
    final prefs = await SharedPreferences.getInstance();
    final global = prefs.getBool(_lockEnabledKey) ?? false;
    if (!global) return false;
    final screenPref = _screenKeys[screenKey];
    if (screenPref == null) return false;
    return prefs.getBool(screenPref) ?? false;
  }

  /// Toggle lock for a specific screen (only works when global lock is ON)
  static Future<void> setScreenLock(String screenKey, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    final screenPref = _screenKeys[screenKey];
    if (screenPref != null) {
      await prefs.setBool(screenPref, enabled);
    }
  }

  /// Check if the device supports biometric/screen lock
  static Future<bool> isDeviceSupported() async {
    if (kIsWeb) return false; // biometrics not available on web
    try {
      return await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  /// Check if biometrics are available
  static Future<bool> hasBiometrics() async {
    if (kIsWeb) return false; // biometrics not available on web
    try {
      return await _localAuth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  /// Authenticate using biometrics or screen lock
  /// Returns true if authentication succeeded
  static Future<bool> authenticate({String? reason}) async {
    if (kIsWeb) return true; // skip biometric auth on web
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

  /// If the given screen is locked, prompt authentication.
  /// Returns true if screen is not locked OR authentication succeeded.
  /// Returns false if screen is locked and authentication failed/cancelled.
  static Future<bool> unlockIfNeeded({String? screenKey, String? reason}) async {
    final enabled = await isLockEnabled();
    if (!enabled) return true;
    if (screenKey != null) {
      final screenLocked = await isScreenLockEnabled(screenKey);
      if (!screenLocked) return true;
    }
    return authenticate(reason: reason);
  }
}
