import 'dart:convert';
import 'dart:io' show Platform, File;
import 'dart:ui' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:instiy/utils/formatters.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final data = message.data;
  final notification = message.notification;
  final type = data['type'] as String? ?? '';
  if (type == 'call' || data.containsKey('call_id')) {
    // Background isolate: the receiver stays silent by design — visual
    // notification only, no audible ring. The caller hears ringback.
    final callId = data['call_id'] as String? ?? 'incoming_call';
    final callerName = data['caller_name'] as String? ?? notification?.title ?? 'Instiy User';
    final callType = data['call_type'] as String? ?? 'voice';
    await LocalNotificationService.showIncomingCallNotification(
      callId: callId,
      callerName: callerName,
      callType: callType,
      callerAvatar: data['caller_avatar'] as String?,
      callerId: data['caller_id'] as String?,
      silent: true,
    );
  }
}

class LocalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Two Android channels:
  //  • _channelId      → plays the device OS sound (used when in-app sound is OFF)
  //  • _silentChannelId → completely silent   (used when in-app sound is ON,
  //                        so AudioPlayer gets clean audio focus)
  static const _channelId = 'instiy_channel';
  static const _channelName = 'Instiy Notifications';
  static const _channelDesc = 'Notifications from Instiy app';

  /// Sentinel matching SoundProvider.deviceDefaultId: the OS default sound.
  static const deviceDefaultSoundId = 'device_default';

  /// Sounds bundled with the app as Android raw resources and iOS caf
  /// files, one per sound id. Each id gets a dedicated Android channel (`instiy_sound_<id>`) whose
  /// configured raw sound the OS plays — foreground and background alike.
  /// Kept in sync with SoundProvider.availableSounds and the push worker's
  /// allow-list.
  static const Map<String, String> notificationSoundNames = {
    'notification_alert': 'Instiy Alert',
    'new_message': 'Instiy New Message',
    'in_chat_message': 'Instiy Chat Message',
    'slack_message': 'Instiy Soft Alert',
    'windows_notification': 'Instiy Note',
    'telegram_notification': 'Instiy Telegram',
    'discord_notification': 'Instiy Discord',
    'pixel_notification': 'Instiy Pixel',
  };

  static String _soundChannelId(String soundId) => 'instiy_sound_$soundId';

  static const _silentChannelId = 'instiy_channel_silent';
  static const _silentChannelName = 'Instiy Notifications (Silent)';
  static const _silentChannelDesc =
      'Silent notifications — in-app sound handles audio';

  static const _callChannelId = 'instiy_incoming_call_channel';
  static const _callChannelName = 'Incoming Calls';
  static const _callChannelDesc = 'Full-screen incoming voice and video calls';

  // Variant used when the app is alive and drives the ringing itself (device
  // call ringer) — the notification must not add its own sound on top.
  static const _silentCallChannelId = 'instiy_incoming_call_channel_silent';
  static const _silentCallChannelName = 'Incoming Calls (In-App Ringing)';
  static const _silentCallChannelDesc =
      'Incoming calls rung by the app — no notification sound';

  static const _soundEnabledKey = 'notification_sound_enabled';
  static const _selectedSoundKey = 'selected_notification_sound';

  static void Function(String action, Map<String, dynamic> data)? onCallActionReceived;

  /// Initialize the local notification plugin and register Android channels.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationBackgroundTapped,
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      // Normal channel — OS plays its own sound
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
          playSound: true,
        ),
      );

      // One channel per bundled sound. Android locks a channel's sound at
      // creation, so each sound needs its own channel id (which is also
      // what the push worker sends as android_channel_id).
      for (final entry in notificationSoundNames.entries) {
        await androidImpl.createNotificationChannel(
          AndroidNotificationChannel(
            _soundChannelId(entry.key),
            'Instiy Notifications (${entry.value})',
            description: 'Instiy notifications with the ${entry.value} sound',
            importance: Importance.high,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(entry.key),
          ),
        );
      }

      // Silent channel — no OS sound; in-app AudioPlayer plays instead
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _silentChannelId,
          _silentChannelName,
          description: _silentChannelDesc,
          importance: Importance.high,
          playSound: false,
        ),
      );

      // Full-screen call channel — Max importance, call category, vibration & sound
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _callChannelId,
          _callChannelName,
          description: _callChannelDesc,
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
        ),
      );

      // Silent twin of the call channel for calls the app rings itself.
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _silentCallChannelId,
          _silentCallChannelName,
          description: _silentCallChannelDesc,
          importance: Importance.max,
          playSound: false,
          enableVibration: true,
          audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
        ),
      );
    }

    _initialized = true;
  }

  @pragma('vm:entry-point')
  static void _onNotificationBackgroundTapped(NotificationResponse response) {
    // Background action handling
  }

  static void _onNotificationTapped(NotificationResponse response) {
    final payloadStr = response.payload;
    if (payloadStr != null && payloadStr.isNotEmpty) {
      try {
        final data = jsonDecode(payloadStr) as Map<String, dynamic>;
        if (data['type'] == 'call') {
          final actionId = response.actionId;
          if (actionId == 'action_decline_call') {
            onCallActionReceived?.call('decline', data);
          } else if (actionId == 'action_accept_call') {
            onCallActionReceived?.call('accept', data);
          } else {
            onCallActionReceived?.call('open', data);
          }
          return;
        }
      } catch (e) {
        debugPrint('LocalNotificationService: payload error: $e');
      }
    }
  }

  /// Read the user's in-app sound preference from SharedPreferences.
  static Future<bool> _isInAppSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true;
  }

  /// The user's chosen notification sound id, validated against the
  /// bundled set ('device_default' passes through). Public so the push
  /// worker sync can read the same value.
  static Future<String> getSelectedSoundId() async {
    final prefs = await SharedPreferences.getInstance();
    final id =
        prefs.getString(_selectedSoundKey) ?? 'notification_alert';
    if (id == deviceDefaultSoundId) return id;
    return notificationSoundNames.containsKey(id) ? id : 'notification_alert';
  }

  /// Maps a notification type to its sound: fixed sounds for messages, the
  /// user's pick for everything else.
  static String _soundIdForType(String? type, String selected) {
    switch (type) {
      case 'message':
      case 'new_message':
        return 'new_message';
      case 'in_chat_message':
        return 'in_chat_message';
      default:
        return selected;
    }
  }

  /// Show a local device notification.
  ///
  /// The sound is strictly OS-level so the user's pick plays identically in
  /// the foreground and the background:
  ///   • sound off     → silent channel, no sound on either platform
  ///   • device default → the OS default sound on both platforms
  ///   • bundled sound  → its Android channel (raw resource) / iOS caf file
  ///
  /// If [inAppSoundEnabled] is not supplied it is read from SharedPreferences.
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool? inAppSoundEnabled,
    String? type,
  }) async {
    final soundEnabled = inAppSoundEnabled ?? await _isInAppSoundEnabled();
    // Resolve once so the channel, the iOS sound, and the push sync agree.
    final soundId =
        soundEnabled ? _soundIdForType(type, await getSelectedSoundId()) : null;
    final formattedTitle = _formatCurrencySymbol(title);
    final formattedBody = _formatCurrencySymbol(body);

    if (!kIsWeb) {
      if (!_initialized) await initialize();

      // Branded tray: the project logo is the large icon for every
      // notification type; the small (status-bar) icon is the white logo
      // silhouette drawable set during initialization.
      const largeIconName = 'logo';
      String? tempFilePath;
      try {
        final byteData = await rootBundle.load('assets/$largeIconName.png');
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$largeIconName.png');
        if (!await file.exists()) {
          await file.writeAsBytes(byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ));
        }
        tempFilePath = file.path;
      } catch (e) {
        debugPrint('Error copying notification icon: $e');
      }

      final String channelId;
      final String channelName;
      final String channelDesc;
      if (soundId == null) {
        channelId = _silentChannelId;
        channelName = _silentChannelName;
        channelDesc = _silentChannelDesc;
      } else if (soundId == deviceDefaultSoundId) {
        channelId = _channelId;
        channelName = _channelName;
        channelDesc = _channelDesc;
      } else {
        channelId = _soundChannelId(soundId);
        channelName =
            'Instiy Notifications (${notificationSoundNames[soundId]})';
        channelDesc = 'Instiy notifications with a custom sound';
      }

      final androidDetails = AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: soundId != null,
        sound: soundId != null && soundId != deviceDefaultSoundId
            ? RawResourceAndroidNotificationSound(soundId)
            : null,
        icon: '@drawable/ic_notification',
        color: const Color(0xFF7C3AED),
        largeIcon: tempFilePath != null
            ? FilePathAndroidBitmap(tempFilePath)
            : const DrawableResourceAndroidBitmap('ic_notification'),
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: soundId != null,
          sound: soundId != null && soundId != deviceDefaultSoundId
              ? '$soundId.caf'
              : null,
          attachments: (Platform.isIOS && tempFilePath != null)
              ? [DarwinNotificationAttachment(tempFilePath)]
              : null,
        ),
      );

      await _plugin.show(
        id: id,
        title: formattedTitle,
        body: formattedBody,
        notificationDetails: details,
        payload: payload,
      );
    }
  }

  /// Generate a unique notification ID from a string.
  static int _generateId(String input) {
    return input.hashCode.abs() % 2147483647;
  }

  /// Listen to new notifications from Supabase and show as device notification.
  static RealtimeChannel? _subscription;

  static void subscribeToNotifications() {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    _unsubscribeFromNotifications();

    _subscription = SupabaseService.client
        .channel('local-notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) async {
            final data = payload.newRecord;
            final title = data['title'] as String? ?? '';
            final body = data['body'] as String? ?? '';
            final type = data['type'] as String? ?? '';
            final id = data['id'] as String? ?? '';

            if (title.isEmpty) return;

            // Read the preference once so both calls use the same value
            final inAppSoundOn = await _isInAppSoundEnabled();

            // Show the OS notification (silenced when in-app sound is on, plays in-app sound)
            await showNotification(
              id: _generateId(id),
              title: title,
              body: body,
              payload: jsonEncode({'type': type, 'id': id}),
              inAppSoundEnabled: inAppSoundOn,
              type: type,
            );
          },
        )
        .subscribe();
  }

  static void _unsubscribeFromNotifications() {
    if (_subscription != null) {
      SupabaseService.client.removeChannel(_subscription!);
      _subscription = null;
    }
  }

  // ─── Helper methods for specific notification types ─────────────

  /// Transfer sent notification
  static Future<void> notifyTransferSent({
    required double amount,
    required String recipientName,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Transfer Sent',
      body: '${formatGhs(amount)} sent to $recipientName',
      type: 'transfer_sent',
    );
  }

  /// Transfer received notification
  static Future<void> notifyTransferReceived({
    required double amount,
    required String senderName,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Transfer Received',
      body: '${formatGhs(amount)} received from $senderName',
      type: 'transfer_received',
    );
  }

  /// Deposit notification
  static Future<void> notifyDeposit({
    required double amount,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Deposit Successful',
      body: '${formatGhs(amount)} has been deposited to your wallet',
      type: 'deposit',
    );
  }

  /// Seller verification approved
  static Future<void> notifyVerificationApproved() async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Verification Approved',
      body:
          'Your seller profile has been verified! You now have a verified badge.',
      type: 'verification_approved',
    );
  }

  /// Seller verification rejected
  static Future<void> notifyVerificationRejected({String? reason}) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Verification Rejected',
      body: reason ??
          'Your verification request was not approved. Please try again.',
      type: 'verification_rejected',
    );
  }

  /// Delivery approved notification
  static Future<void> notifyDeliveryApproved({
    required String productTitle,
    required double amount,
    double deliveryFee = 0.0,
  }) async {
    final body = deliveryFee > 0
        ? 'Delivery confirmed for "$productTitle". ${formatGhs(amount)} released to your wallet (incl. ${formatGhs(deliveryFee)} delivery fee).'
        : 'Delivery confirmed for "$productTitle". ${formatGhs(amount)} released to your wallet.';
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Delivery Confirmed',
      body: body,
      type: 'delivery_approved',
    );
  }

  /// New message notification
  static Future<void> notifyNewMessage({
    required String senderName,
    required String message,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'New Message from $senderName',
      body: message,
      type: 'new_message',
    );
  }

  /// Order placed notification
  static Future<void> notifyOrderPlaced({
    required String orderId,
    required double amount,
    double deliveryFee = 0.0,
  }) async {
    final body = deliveryFee > 0
        ? 'Order #${orderId.substring(0, 8).toUpperCase()} placed for ${formatGhs(amount)} (incl. ${formatGhs(deliveryFee)} delivery fee)'
        : 'Order #${orderId.substring(0, 8).toUpperCase()} placed for ${formatGhs(amount)}';
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Order Placed',
      body: body,
      type: 'order',
    );
  }

  /// Withdrawal processed
  static Future<void> notifyWithdrawalProcessed({
    required double amount,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch % 2147483647,
      title: 'Withdrawal Processed',
      body:
          'Your withdrawal of ${formatGhs(amount)} has been processed.',
      type: 'withdrawal',
    );
  }

  /// Show a full-screen WhatsApp-style incoming call notification.
  ///
  /// Always silent for incoming calls: the receiver's phone never rings
  /// audibly (vibration only) while the caller hears ringback. The [silent]
  /// flag picks the silent Android channel; pass false only to allow the OS
  /// notification sound.
  static Future<void> showIncomingCallNotification({
    required String callId,
    required String callerName,
    required String callType,
    String? callerAvatar,
    String? callerId,
    bool silent = false,
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();

    final isVideo = callType == 'video';
    final title = callerName.isNotEmpty ? callerName : 'Instiy Call';
    final body = isVideo ? 'Incoming video call…' : 'Incoming voice call…';
    final notifId = _generateId('call_$callId');

    const largeIconName = 'logo';
    String? tempFilePath;
    try {
      final byteData = await rootBundle.load('assets/$largeIconName.png');
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$largeIconName.png');
      if (!await file.exists()) {
        await file.writeAsBytes(byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ));
      }
      tempFilePath = file.path;
    } catch (_) {}

    final androidDetails = AndroidNotificationDetails(
      silent ? _silentCallChannelId : _callChannelId,
      silent ? _silentCallChannelName : _callChannelName,
      channelDescription:
          silent ? _silentCallChannelDesc : _callChannelDesc,
      importance: Importance.max,
      priority: Priority.max,
      category: AndroidNotificationCategory.call,
      audioAttributesUsage: AudioAttributesUsage.voiceCommunication,
      fullScreenIntent: true,
      ongoing: true,
      autoCancel: false,
      timeoutAfter: 30000,
      playSound: !silent,
      icon: '@drawable/ic_notification',
      color: const Color(0xFF7C3AED),
      largeIcon: tempFilePath != null
          ? FilePathAndroidBitmap(tempFilePath)
          : const DrawableResourceAndroidBitmap('ic_notification'),
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'action_accept_call',
          'Accept',
          titleColor: Color(0xFF22C55E),
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          'action_decline_call',
          'Decline',
          titleColor: Color(0xFFEF4444),
          cancelNotification: true,
        ),
      ],
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: false,
        presentBanner: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );

    await _plugin.show(
      id: notifId,
      title: title,
      body: body,
      notificationDetails: details,
      payload: jsonEncode({
        'type': 'call',
        'call_id': callId,
        'caller_id': callerId,
        'caller_name': callerName,
        'call_type': callType,
        'caller_avatar': callerAvatar,
      }),
    );
  }

  /// Cancel an active incoming call notification.
  static Future<void> cancelCallNotification(String callId) async {
    if (kIsWeb) return;
    try {
      await _plugin.cancel(id: _generateId('call_$callId'));
    } catch (_) {}
  }

  /// Set up Firebase Cloud Messaging background and foreground event listeners silently on startup.
  static Future<void> setupFcmListeners() async {
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;

    // 1. Foreground message listener (triggers local notification popups or call screen)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;
      final data = message.data;
      final type = data['type'] as String? ?? '';

      if (type == 'call' || data.containsKey('call_id')) {
        // Silent visual notification only — the receiver never rings
        // audibly; the caller hears ringback. Realtime invites drive the
        // in-app incoming screen when the app is alive.
        final callId = data['call_id'] as String? ?? 'incoming_call';
        final callerName = data['caller_name'] as String? ?? notification?.title ?? 'Instiy User';
        final callType = data['call_type'] as String? ?? 'voice';
        await showIncomingCallNotification(
          callId: callId,
          callerName: callerName,
          callType: callType,
          callerAvatar: data['caller_avatar'] as String?,
          callerId: data['caller_id'] as String?,
          silent: true,
        );
        return;
      }
      
      if (notification != null) {
        final useInAppSound = await _isInAppSoundEnabled();
        
        await showNotification(
          id: notification.hashCode,
          title: notification.title ?? 'New Notification',
          body: notification.body ?? '',
          payload: jsonEncode(data),
          inAppSoundEnabled: useInAppSound,
          type: data['type'] as String?,
        );
      }
    });

    // 2. Message tap listener when the app was running in background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationPayload(message.data);
    });

    // 3. Handle notification click if the app was completely terminated
    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationPayload(initialMessage.data);
    }

    // 4. Listen to token refreshes to keep DB updated
    messaging.onTokenRefresh.listen((newToken) async {
      await saveTokenToDatabase(newToken);
    });
  }


  /// Check if the authenticated user has a registered push token in the DB.
  /// Request notification permission if needed and always ensure the current
  /// FCM token is persisted.
  static Future<void> checkAndPromptFcmForAuthenticatedUser() async {
    if (kIsWeb) return;
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    // 1. Request notification permission (handles both local + push).
    //    On Android 13+ this shows the POST_NOTIFICATIONS system dialog.
    //    On iOS, Firebase's requestPermission handles the prompt.
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final androidImpl = _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        final granted = await androidImpl?.requestNotificationsPermission();
        debugPrint('Android notification permission granted: $granted');
      }

      // Firebase permission request — on Android this is a no-op if the
      // system permission was already granted above; on iOS this shows
      // the native prompt.
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('Notification permission not granted: ${settings.authorizationStatus}');
        return;
      }
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      // Continue anyway — token retrieval may still work on some devices
    }

    // 2. Always retrieve the current FCM token and persist it.
    //    This handles first-time registration, token refreshes, and
    //    re-installs where the old token is stale.
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      debugPrint('FCM token retrieved: ${token != null ? '${token.substring(0, 10)}...' : 'null'}');
      if (token != null) {
        await saveTokenToDatabase(token);
      }
    } catch (e) {
      debugPrint('Error retrieving/saving FCM token: $e');
    }
  }

  /// Save the FCM push token to the user_push_tokens table in Supabase.
  ///
  /// Deletes any existing tokens for this user first (handles token rotation),
  /// then inserts the current token.
  static Future<void> saveTokenToDatabase(String token) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Upsert the token to associate it with the current user, updating it if it already exists
      await SupabaseService.client.from('user_push_tokens').upsert({
        'user_id': userId,
        'token': token,
        'sound': await getSelectedSoundId(),
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('Push token saved to database successfully');
    } catch (e) {
      // The sound column may not exist yet if its migration hasn't been
      // applied — retry without it so token registration never breaks.
      if ('$e'.contains("'sound'")) {
        try {
          await SupabaseService.client.from('user_push_tokens').upsert({
            'user_id': userId,
            'token': token,
            'updated_at': DateTime.now().toIso8601String(),
          });
          debugPrint('Push token saved to database successfully');
          return;
        } catch (_) {}
      }
      debugPrint('Error saving push token to database: $e');
    }
  }

  /// Push the user's chosen notification sound to their token rows so
  /// background pushes address the same OS sound. Best-effort: the local
  /// choice applies immediately regardless of the outcome.
  static Future<void> updatePushSound(String soundId) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await SupabaseService.client
          .from('user_push_tokens')
          .update({'sound': soundId})
          .eq('user_id', userId);
    } catch (e) {
      debugPrint('Error syncing push sound: $e');
    }
  }

  /// Handle notification payload redirects inside the app on click
  static void _handleNotificationPayload(Map<String, dynamic> data) {
    if (data['type'] == 'call' || data.containsKey('call_id')) {
      onCallActionReceived?.call('open', data);
    }
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  static String _formatCurrencySymbol(String text) {
    return text
        .replaceAll(r'GH\u00a2', 'GH₵')
        .replaceAll(r'GH\\u00a2', 'GH₵')
        .replaceAll(r'\u00a2', '₵')
        .replaceAll(r'\\u00a2', '₵')
        .replaceAll('GH¢', 'GH₵')
        .replaceAll('¢', '₵');
  }
}
