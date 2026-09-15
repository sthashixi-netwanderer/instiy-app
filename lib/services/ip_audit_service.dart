import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../screens/info/blocked_ip_screen.dart';
import 'navigation_service.dart';
import 'supabase_service.dart';

/// Outcome of a session-audit call: the caller's public IP and whether the
/// worker reports it as blocked.
class IpAuditStatus {
  const IpAuditStatus({
    required this.ip,
    required this.blocked,
    this.reason,
  });

  final String ip;
  final bool blocked;
  final String? reason;
}

/// Records app sessions/logins in the admin IP audit trail and enforces the
/// cooperative IP blocklist: when the worker says the current public IP is
/// blocked, the whole nav stack is replaced with [BlockedIpScreen]. Every
/// failure is swallowed — auditing must never affect the user.
class IpAuditService {
  IpAuditService._();

  static final IpAuditService instance = IpAuditService._();

  String? _platform;
  String? _osVersion;
  String? _deviceModel;
  String? _appVersion;

  /// Records the event and handles the lockout when blocked. Never throws.
  Future<void> recordAndHandle(String eventType) async {
    final status = await record(eventType);
    if (status == null || !status.blocked) return;
    final nav = NavigationService.navigatorKey.currentState;
    if (nav == null) return;
    await nav.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => BlockedIpScreen(reason: status.reason),
      ),
      (route) => false,
    );
  }

  /// Returns null when the call fails for any reason.
  Future<IpAuditStatus?> record(String eventType) async {
    try {
      await _collectDeviceInfo();
      final data = await SupabaseService.callFunction(
        'session-audit',
        body: {
          'eventType': eventType,
          'platform': _platform,
          'osVersion': _osVersion,
          'deviceModel': _deviceModel,
          'appVersion': _appVersion,
        },
      );
      return IpAuditStatus(
        ip: (data['ip'] as String?) ?? '',
        blocked: data['blocked'] == true,
        reason: data['reason'] as String?,
      );
    } catch (e) {
      debugPrint('IpAuditService: session-audit failed: $e');
      return null;
    }
  }

  /// Collects device/app info once per process and caches it.
  Future<void> _collectDeviceInfo() async {
    if (_appVersion != null) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _appVersion = info.version;
    } catch (_) {}
    try {
      if (kIsWeb) {
        _platform = 'web';
        return;
      }
      final device = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await device.androidInfo;
        _platform = 'android';
        _osVersion = 'Android ${android.version.release}';
        _deviceModel = android.model;
      } else if (Platform.isIOS) {
        final ios = await device.iosInfo;
        _platform = 'ios';
        _osVersion = ios.systemVersion;
        _deviceModel = ios.utsname.machine;
      } else {
        _platform = Platform.operatingSystem;
        _osVersion = Platform.operatingSystemVersion;
      }
    } catch (_) {}
  }
}
