import 'dart:convert';
import 'dart:io' show Platform, File;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'sound_service.dart';
import 'supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background push notification entry point — show a local notification
  // so the user sees something even when the app is terminated/background
  final notification = message.notification;
  if (notification == null) return;

  final plugin = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    ),
  );

  final data = message.data;
  final type = data['type'] as String?;

  String largeIconName = 'ic_notification_default';
  switch (type) {
    case 'order':
      largeIconName = 'ic_notification_order';
      break;
    case 'message':
    case 'new_message':
      largeIconName = 'ic_notification_message';
      break;
    case 'transfer_sent':
    case 'withdrawal':
      largeIconName = 'ic_notification_wallet_sent';
      break;
    case 'transfer_received':
    case 'deposit':
      largeIconName = 'ic_notification_wallet_received';
      break;
    case 'verification_approved':
      largeIconName = 'ic_notification_verification_approved';
      break;
    case 'verification_rejected':
      largeIconName = 'ic_notification_verification_rejected';
      break;
    case 'delivery':
    case 'delivery_approved':
      largeIconName = 'ic_notification_delivery';
      break;
    case 'review':
      largeIconName = 'ic_notification_review';
      break;
  }

  String? tempFilePath;
  if (!kIsWeb) {
    try {
      final byteData = await rootBundle.load('assets/notification_icons/$largeIconName.png');
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
      debugPrint('Error copying notification icon in background: $e');
    }
  }

  final androidDetails = AndroidNotificationDetails(
    'instiy_channel',
    'Instiy Notifications',
    channelDescription: 'Notifications from Instiy app',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
    largeIcon: tempFilePath != null
        ? FilePathAndroidBitmap(tempFilePath)
        : DrawableResourceAndroidBitmap(largeIconName),
  );
  
  final details = NotificationDetails(
    android: androidDetails,
    iOS: DarwinNotificationDetails(
      attachments: (Platform.isIOS && tempFilePath != null)
          ? [DarwinNotificationAttachment(tempFilePath)]
          : null,
    ),
  );

  await plugin.show(
    id: notification.hashCode,
    title: notification.title ?? 'New Notification',
    body: notification.body ?? '',
    notificationDetails: details,
  );
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

  static const _silentChannelId = 'instiy_channel_silent';
  static const _silentChannelName = 'Instiy Notifications (Silent)';
  static const _silentChannelDesc =
      'Silent notifications — in-app sound handles audio';

  static const _soundEnabledKey = 'notification_sound_enabled';

  /// Initialize the local notification plugin and register both Android channels.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
    );

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImpl != null) {
      // NOTE: Do NOT request notification permission here.
      // Permission is requested after authentication via
      // checkAndPromptFcmForAuthenticatedUser() so the FCM token
      // can be saved to the database immediately.
      // Requesting before auth means if the user denies, the OS
      // won't show the dialog again after login.

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

      // Silent channel — no OS sound; in-app AudioPlayer plays instead
      await androidImpl.createNotificationChannel(
        const AndroidNotificationChannel(
          _silentChannelId,
          _silentChannelName,
          description: _silentChannelDesc,
          importance: Importance.high,
          playSound: false,
          // enableVibration kept true so the device still vibrates
        ),
      );
    }

    _initialized = true;
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap — navigate to relevant screen
  }

  /// Read the user's in-app sound preference from SharedPreferences.
  static Future<bool> _isInAppSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true;
  }

  /// Show a local device notification.
  ///
  /// [inAppSoundEnabled] controls which channel is used:
  ///   • true  → silent channel (AudioPlayer will play the in-app sound)
  ///   • false → normal channel (OS plays its own notification sound)
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
    final useInAppSound = inAppSoundEnabled ?? await _isInAppSoundEnabled();

    if (!kIsWeb) {
      if (!_initialized) await initialize();

      String largeIconName = 'ic_notification_default';
      switch (type) {
        case 'order':
          largeIconName = 'ic_notification_order';
          break;
        case 'message':
        case 'new_message':
          largeIconName = 'ic_notification_message';
          break;
        case 'transfer_sent':
        case 'withdrawal':
          largeIconName = 'ic_notification_wallet_sent';
          break;
        case 'transfer_received':
        case 'deposit':
          largeIconName = 'ic_notification_wallet_received';
          break;
        case 'verification_approved':
          largeIconName = 'ic_notification_verification_approved';
          break;
        case 'verification_rejected':
          largeIconName = 'ic_notification_verification_rejected';
          break;
        case 'delivery':
        case 'delivery_approved':
          largeIconName = 'ic_notification_delivery';
          break;
        case 'review':
          largeIconName = 'ic_notification_review';
          break;
      }

      String? tempFilePath;
      if (!kIsWeb) {
        try {
          final byteData = await rootBundle.load('assets/notification_icons/$largeIconName.png');
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
      }

      final androidDetails = AndroidNotificationDetails(
        useInAppSound ? _silentChannelId : _channelId,
        useInAppSound ? _silentChannelName : _channelName,
        channelDescription: useInAppSound ? _silentChannelDesc : _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        playSound: !useInAppSound, // OS sound only when in-app sound is off
        icon: '@mipmap/ic_launcher',
        largeIcon: tempFilePath != null
            ? FilePathAndroidBitmap(tempFilePath)
            : DrawableResourceAndroidBitmap(largeIconName),
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          // Suppress iOS system sound when in-app sound is on
          presentSound: !useInAppSound,
          attachments: (Platform.isIOS && tempFilePath != null)
              ? [DarwinNotificationAttachment(tempFilePath)]
              : null,
        ),
      );

      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: details,
        payload: payload,
      );
    }

    if (useInAppSound) {
      if (type != null) {
        await SoundService.playSoundForType(type);
      } else {
        await SoundService.playNotificationSound();
      }
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
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Transfer Sent',
      body: 'GH¢ ${amount.toStringAsFixed(2)} sent to $recipientName',
      type: 'transfer_sent',
    );
  }

  /// Transfer received notification
  static Future<void> notifyTransferReceived({
    required double amount,
    required String senderName,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Transfer Received',
      body: 'GH¢ ${amount.toStringAsFixed(2)} received from $senderName',
      type: 'transfer_received',
    );
  }

  /// Deposit notification
  static Future<void> notifyDeposit({
    required double amount,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Deposit Successful',
      body: 'GH¢ ${amount.toStringAsFixed(2)} has been deposited to your wallet',
      type: 'deposit',
    );
  }

  /// Seller verification approved
  static Future<void> notifyVerificationApproved() async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Verification Approved',
      body:
          'Your seller profile has been verified! You now have a verified badge.',
      type: 'verification_approved',
    );
  }

  /// Seller verification rejected
  static Future<void> notifyVerificationRejected({String? reason}) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
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
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Delivery Confirmed',
      body:
          'Delivery confirmed for "$productTitle". GH¢ ${amount.toStringAsFixed(2)} released to your wallet.',
      type: 'delivery_approved',
    );
  }

  /// New message notification
  static Future<void> notifyNewMessage({
    required String senderName,
    required String message,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'New Message from $senderName',
      body: message,
      type: 'new_message',
    );
  }

  /// Order placed notification
  static Future<void> notifyOrderPlaced({
    required String orderId,
    required double amount,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Order Placed',
      body:
          'Order #${orderId.substring(0, 8).toUpperCase()} placed for GH¢ ${amount.toStringAsFixed(2)}',
      type: 'order',
    );
  }

  /// Withdrawal processed
  static Future<void> notifyWithdrawalProcessed({
    required double amount,
  }) async {
    await showNotification(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: 'Withdrawal Processed',
      body:
          'Your withdrawal of GH¢ ${amount.toStringAsFixed(2)} has been processed.',
      type: 'withdrawal',
    );
  }

  /// Set up Firebase Cloud Messaging background and foreground event listeners silently on startup.
  static Future<void> setupFcmListeners() async {
    if (kIsWeb) return;
    final messaging = FirebaseMessaging.instance;

    // 1. Foreground message listener (triggers local notification popups)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final notification = message.notification;
      final data = message.data;
      
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
      // Remove any stale tokens for this user to avoid duplicates
      await SupabaseService.client
          .from('user_push_tokens')
          .delete()
          .eq('user_id', userId);

      // Insert the fresh token
      await SupabaseService.client.from('user_push_tokens').insert({
        'user_id': userId,
        'token': token,
        'updated_at': DateTime.now().toIso8601String(),
      });
      debugPrint('Push token saved to database successfully');
    } catch (e) {
      debugPrint('Error saving push token to database: $e');
    }
  }

  /// Handle notification payload redirects inside the app on click
  static void _handleNotificationPayload(Map<String, dynamic> data) {
    // Allows deep-linking to specific screens from the push data in production
  }

  /// Cancel all notifications
  static Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
