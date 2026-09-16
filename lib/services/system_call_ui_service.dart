import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/notification_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

/// WhatsApp-style incoming-call presentation: the OS call UI
/// (ConnectionService full-screen on Android, CallKit on iOS) ringing with
/// the phone's own ringtone instead of an in-app sound.
///
/// Research notes (flutter_callkit_incoming v3, verified against source):
/// - `ringtonePath: 'system_ringtone_default'` resolves to
///   `RingtoneManager.getActualDefaultRingtoneUri(TYPE_RINGTONE)` on
///   Android and the system ringtone on iOS — the user's ringtone, volume
///   and silent-mode handling all apply.
/// - `type: 1` marks a video call (`type > 0` shows the video accept
///   affordance); `0` is audio.
/// - `duration` is milliseconds on both platforms (Android
///   `setTimeoutAfter`, iOS `.milliseconds` deadline) — kept equal to the
///   signaling ring timeout so both sides stop together.
/// - Our signaling call id (UUID v4) is reused as the system call id, so
///   plugin events correlate without a mapping table. iOS ignores invalid
///   UUIDs, hence [isValidCallUuid].
/// - iOS shows this UI whenever the app is alive (foreground/background).
///   Waking a *terminated* iOS app additionally needs PushKit + a VoIP
///   certificate + server-side VoIP pushes, which is not wired yet — see
///   the note on [showIncomingCall].
class SystemCallUiService {
  static const _appName = 'Instiy';

  /// Ring timeout in ms — matches the signaling layer's 30s no-answer
  /// timer so the system UI and the session expire together.
  static const int ringTimeoutMs = 30000;

  /// Value passed as `ringtonePath` on both platforms: the phone's
  /// default ringtone, not a bundled sound.
  static const _systemRingtone = 'system_ringtone_default';

  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// iOS drops system calls whose id is not a UUID — callers must fall
  /// back to the local notification path when this is false.
  static bool isValidCallUuid(String id) => _uuidPattern.hasMatch(id);

  static CallKitParams buildParams({
    required String callId,
    required String callerName,
    String? callerAvatar,
    required bool video,
    required Map<String, dynamic> extra,
  }) {
    final displayName =
        callerName.isNotEmpty ? callerName : 'Instiy User';
    return CallKitParams(
      id: callId,
      nameCaller: displayName,
      appName: _appName,
      avatar: (callerAvatar?.isNotEmpty == true) ? callerAvatar : null,
      handle: displayName,
      type: video ? 1 : 0,
      duration: ringTimeoutMs,
      extra: extra,
      missedCallNotification: const NotificationParams(
        showNotification: true,
        isShowCallback: true,
        subtitle: 'Missed call',
        callbackText: 'Call back',
      ),
      android: const AndroidParams(
        ringtonePath: _systemRingtone,
        incomingCallNotificationChannelName: 'Incoming Calls',
        missedCallNotificationChannelName: 'Missed Calls',
        textAccept: 'Accept',
        textDecline: 'Decline',
        isShowCallID: false,
      ),
      ios: IOSParams(
        ringtonePath: _systemRingtone,
        handleType: 'generic',
        supportsVideo: video,
      ),
    );
  }

  /// Shows the system incoming-call UI. Returns true when it is up (and
  /// ringing the phone ringtone); false when the caller should use the
  /// local-notification + in-app/device-ringer fallback instead.
  static Future<bool> showIncomingCall({
    required String callId,
    required String callerName,
    String? callerAvatar,
    required bool video,
    required Map<String, dynamic> extra,
  }) async {
    if (!isSupported || !isValidCallUuid(callId)) return false;
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(
        buildParams(
          callId: callId,
          callerName: callerName,
          callerAvatar: callerAvatar,
          video: video,
          extra: extra,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('SystemCallUi: show failed, using fallback: $e');
      return false;
    }
  }

  /// Builds the call payload from an FCM data map (keys match the push
  /// trigger + signaling payloads) and shows the system UI unless it is
  /// already showing this call (Realtime and FCM can both deliver it).
  static Future<bool> showFromPush(
    Map<String, dynamic> data, {
    String? fallbackTitle,
  }) async {
    final callId = data['call_id'] as String?;
    if (callId == null || !isValidCallUuid(callId)) return false;
    if (await isShowing(callId)) return true;
    final callerName =
        (data['caller_name'] as String?) ?? fallbackTitle ?? 'Instiy User';
    return showIncomingCall(
      callId: callId,
      callerName: callerName,
      callerAvatar: data['caller_avatar'] as String?,
      video: (data['call_type'] as String?) == 'video',
      extra: {
        'call_id': callId,
        'caller_id': data['caller_id'],
        'caller_name': callerName,
        'caller_avatar': data['caller_avatar'],
        'call_type': (data['call_type'] as String?) ?? 'voice',
      },
    );
  }

  /// True when the system UI is already displaying this call — used to
  /// de-duplicate the Realtime invite path and the FCM path.
  static Future<bool> isShowing(String callId) async {
    if (!isSupported) return false;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return calls.any((c) => c.id == callId);
    } catch (_) {
      return false;
    }
  }

  /// Dismisses the system UI for a call (accept/decline/timeout/cancel —
  /// the single choke point, mirroring the local-notification cancel).
  static Future<void> dismiss(String callId) async {
    if (!isSupported) return;
    try {
      await FlutterCallkitIncoming.endCall(callId);
    } catch (_) {}
  }

  /// Drops orphaned system UI left by a previous run — sessions never
  /// survive a restart, so anything still displayed is stale.
  static Future<void> clearAll() async {
    if (!isSupported) return;
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }
}
