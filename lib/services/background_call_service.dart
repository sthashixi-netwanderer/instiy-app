import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'supabase_service.dart';

/// User-controlled background ("unrestricted") mode for receiving calls.
///
/// When enabled on Android, a foreground service keeps the app process alive
/// while it is backgrounded so the Supabase Realtime socket — and therefore
/// incoming call invites — keep flowing. The user is also offered the
/// battery-optimization exemption ("unrestricted") so Doze cannot throttle
/// the connection. Everything is opt-in: the service only runs while the
/// toggle is on.
class BackgroundCallService {
  BackgroundCallService._();

  static final BackgroundCallService instance = BackgroundCallService._();

  static const String _prefsKey = 'background_calls_enabled';
  static const String _channelId = 'instiy_background_calls';
  static const String _channelName = 'Background Calls';
  static const String _channelDesc =
      'Keeps Instiy connected so incoming calls are received while the app '
      'is in the background';

  bool _initialized = false;
  bool _enabled = false;
  AppLifecycleListener? _keepAliveListener;
  int _lifecycleGeneration = 0;

  bool get isEnabled => _enabled;
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefsKey) ?? false;

    if (!isSupported) return;

    // The service isolate only exists to own the foreground notification and
    // keep the process eligible; the realtime connection lives in the main
    // isolate, which keeps running under the foreground service.
    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: _enabled,
        autoStartOnBoot: false,
        isForegroundMode: true,
        notificationChannelId: _channelId,
        initialNotificationTitle: 'Instiy',
        initialNotificationContent:
            'Connected in the background to receive calls',
        foregroundServiceTypes: const [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(),
    );

    _installKeepAlive();

    if (_enabled) {
      await _startServiceIfNotRunning();
    }
  }

  /// The foreground-service isolate entry point. Must never return.
  @pragma('vm:entry-point')
  static void _onServiceStart(ServiceInstance service) async {
    // Keep the isolate alive; all call logic runs in the main isolate.
    Timer.periodic(const Duration(minutes: 1), (_) {});
  }

  /// Enables or disables background mode. Returns false when the user backs
  /// out of the permission dialog — the toggle should reflect that.
  Future<bool> setEnabled(bool value) async {
    if (!isSupported) return false;

    if (value) {
      final granted = await _requestUnrestrictedPermissions();
      if (!granted) return false;
    }

    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, value);

    final service = FlutterBackgroundService();
    if (value) {
      await _startServiceIfNotRunning();
    } else if (await service.isRunning()) {
      service.invoke('stopService');
    }
    return true;
  }

  Future<bool> isServiceRunning() async {
    if (!isSupported) return false;
    try {
      return await FlutterBackgroundService().isRunning();
    } catch (_) {
      return false;
    }
  }

  /// Requests the permissions "unrestricted" mode needs: notifications (the
  /// foreground-service notification and incoming-call alerts) and the
  /// battery-optimization exemption. Returns true when the user accepted.
  Future<bool> _requestUnrestrictedPermissions() async {
    try {
      final notifications = await Permission.notification.request();
      if (notifications.isDenied || notifications.isPermanentlyDenied) {
        return false;
      }
      // Opens the system "allow unrestricted data usage" style dialog.
      // A denial here still leaves the foreground service functional (it
      // survives most Doze situations), so accept either outcome.
      await Permission.ignoreBatteryOptimizations.request();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _startServiceIfNotRunning() async {
    try {
      final service = FlutterBackgroundService();
      if (await service.isRunning()) return;
      await _ensureChannel();
      await service.startService();
    } catch (e) {
      debugPrint('BackgroundCallService: start failed: $e');
    }
  }

  Future<void> _ensureChannel() async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.low,
        ),
      );
    } catch (_) {}
  }

  /// supabase_flutter's internal lifecycle listener disconnects the realtime
  /// WebSocket whenever the app pauses (to save battery) with no way to opt
  /// out. With the foreground service active the process stays eligible, so
  /// this listener reconnects the socket shortly after that disconnect and
  /// rejoins the channels (mirroring the SDK's own resume logic).
  void _installKeepAlive() {
    _keepAliveListener?.dispose();
    _keepAliveListener = AppLifecycleListener(
      onStateChange: (state) => _onLifecycleState(state),
    );
  }

  Future<void> _onLifecycleState(AppLifecycleState state) async {
    if (state != AppLifecycleState.paused) return;
    if (!_enabled) return;

    final generation = ++_lifecycleGeneration;
    // Let the SDK's pause-disconnect land first.
    await Future<void>.delayed(const Duration(seconds: 2));

    // The app resumed (or paused again) in the meantime — a newer lifecycle
    // event is handling the state now.
    if (generation != _lifecycleGeneration) return;

    try {
      final realtime = SupabaseService.client.realtime;
      if (realtime.isConnected) return;
      // ignore: invalid_use_of_internal_member
      await realtime.connect();
      if (generation != _lifecycleGeneration) return;
      for (final channel in realtime.channels) {
        // ignore: invalid_use_of_internal_member
        if (channel.isJoined) {
          // ignore: invalid_use_of_internal_member
          channel.forceRejoin();
        }
      }
      debugPrint('BackgroundCallService: realtime reconnected in background');
    } catch (e) {
      debugPrint('BackgroundCallService: background reconnect failed: $e');
    }
  }
}
