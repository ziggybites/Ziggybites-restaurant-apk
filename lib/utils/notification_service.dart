import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:webview_master_app/services/api_service.dart';
import 'package:webview_master_app/config/app_config.dart';
import 'package:webview_master_app/utils/new_order_notification_util.dart';
import 'package:webview_master_app/utils/notification_payload_util.dart';
import 'package:webview_master_app/utils/prefs_util.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import 'dart:io' show Platform;
import 'dart:convert';

/// Notification Service - Handles system tray notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  FirebaseMessaging? _firebaseMessaging;

  bool _isInitialized = false;
  bool _listenersRegistered = false;
  static const _platform = MethodChannel('com.ziggybites.vendor/geolocation');

  // Track shown notifications to prevent duplicates
  final Set<String> _shownNotificationIds = <String>{};
  final Map<String, DateTime> _notificationTimestamps = <String, DateTime>{};

  // Stream for notification taps
  final _tapController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get onTap => _tapController.stream;

  // Cold-start tap: set when the app is launched by tapping a notification while killed.
  // The broadcast stream fires before WebViewScreen can subscribe, so we store the data
  // here so the screen can pull it after the WebView finishes loading.
  Map<String, dynamic>? _coldStartTapData;
  Map<String, dynamic>? get coldStartTapData => _coldStartTapData;
  void consumeColdStartTap() => _coldStartTapData = null;

  /// Strict evaluation logic to check for explicit new order criteria only
  static bool isNewOrderNotification(Map<String, dynamic> data) {
    final type =
        (data['type'] ??
                data['notification_type'] ??
                data['click_action'] ??
                data['event'] ??
                '')
            .toString()
            .toLowerCase()
            .trim();

    final title = (data['title'] ?? '').toString().toLowerCase().trim();
    final body = (data['body'] ?? '').toString().toLowerCase().trim();

    debugPrint(
      '🔔 Notification Check => type="$type", title="$title", body="$body"',
    );

    // Reject immediate non-order patterns
    if (title.contains('rider arrived') || body.contains('rider arrived')) {
      return false;
    }

    // Text Keyword Fallback Match
    if (title.contains('new order') ||
        title.contains('order received') ||
        title.contains('naya order') ||
        body.contains('new order') ||
        body.contains('order received') ||
        body.contains('naya order')) {
      return true;
    }

    // Strict Target Whitelist Filter Mapping
    const newOrderTypes = {
      'new_order',
      'new_order!',
      'new-order',
      'neworder',
      'create_order',
      'order_placed',
      'order_created',
      'place_order',
      'order',
    };

    if (newOrderTypes.contains(type)) {
      return true;
    }

    return false;
  }

  /// Initialize notification service
  Future<void> initialize({bool isBackground = false}) async {
    if (_isInitialized) return;

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings(AppConfig.notificationIcon);

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapped,
    );

    if (!isBackground) {
      final androidPlugin = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      try {
        await androidPlugin?.requestNotificationsPermission();
      } catch (e) {
        debugPrint('⚠️ Foreground permission request skipped: $e');
      }
    }

    await _createNotificationChannel();
    await _initializeFirebaseMessaging();

    _isInitialized = true;
    debugPrint(
      '✅ Notification service initialized (isBackground: $isBackground)',
    );
  }

  /// Initialize Firebase Cloud Messaging Configuration
  Future<void> _initializeFirebaseMessaging() async {
    try {
      _firebaseMessaging = FirebaseMessaging.instance;

      if (Platform.isIOS) {
        final NotificationSettings settings = await _firebaseMessaging!
            .requestPermission(
              alert: true,
              badge: true,
              sound: true,
              provisional: false,
            );
        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          debugPrint('✅ Firebase notification permission granted (iOS)');
        }
        try {
          String? apnsToken = await _firebaseMessaging!.getAPNSToken();
          debugPrint('📱 APNs Token: $apnsToken');
        } catch (e) {
          debugPrint('⚠️ Error getting APNs token: $e');
        }
      }

      final String? token = await _firebaseMessaging!.getToken();
      if (token != null) {
        debugPrint('📱 FCM Token: $token');
      }

      _firebaseMessaging!.onTokenRefresh.listen((newToken) async {
        await saveFCMTokenToBackend(phone: PrefsUtil.getPhoneNumber());
      });

      if (Platform.isIOS) {
        await _firebaseMessaging!.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Guard: register listeners only once per isolate. FirebaseMessaging streams
      // are global process-level event broadcasters; re-registering adds a duplicate
      // listener without removing the old one, causing every message to be handled N times.
      if (!_listenersRegistered) {
        _listenersRegistered = true;

        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          await _handleForegroundMessage(message);
        });

        FirebaseMessaging.onMessageOpenedApp.listen((
          RemoteMessage message,
        ) async {
          debugPrint('🔔 App opened from notification: ${message.data}');
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            message.data,
          );
          if (message.notification != null) {
            data['title'] = message.notification!.title;
            data['body'] = message.notification!.body;
          }
          _handleNotificationTap(data);
        });
      }
    } catch (e) {
      debugPrint('❌ Error initializing Firebase Messaging: $e');
    }
  }

  /// Check for initial notification when app launched from terminated state
  Future<void> checkForInitialNotification() async {
    try {
      final NotificationAppLaunchDetails? launchDetails =
          await _notificationsPlugin.getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse != null) {
        _onNotificationTapped(launchDetails.notificationResponse!);
      }

      if (_firebaseMessaging != null) {
        RemoteMessage? initialMessage = await _firebaseMessaging!
            .getInitialMessage();
        if (initialMessage != null) {
          debugPrint(
            '🔔 App launched from terminated state via FCM: ${initialMessage.data}',
          );
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            initialMessage.data,
          );
          if (initialMessage.notification != null) {
            data['title'] = initialMessage.notification!.title;
            data['body'] = initialMessage.notification!.body;
          }
          _handleNotificationTap(data);
        }
      }
    } catch (e) {
      debugPrint('❌ Error checking initial notification: $e');
    }
  }

  /// Process foreground notifications systematically using precise validation filters
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final RemoteNotification? notification = message.notification;
    final Map<String, dynamic> data = Map<String, dynamic>.from(message.data);

    if (notification != null) {
      if (!data.containsKey('title') || data['title'] == null) {
        data['title'] = notification.title;
      }
      if (!data.containsKey('body') || data['body'] == null) {
        data['body'] = notification.body;
      }
    }

    final String notificationId = message.messageId ?? '';
    final String uniqueId = notificationId.isNotEmpty
        ? notificationId
        : '${data['type'] ?? ''}_${data['orderId'] ?? data['order_id'] ?? ''}_'
              '${notification?.title ?? data['title'] ?? ''}_'
              '${notification?.body ?? data['body'] ?? ''}';

    _cleanOldNotificationIds();

    if (_shownNotificationIds.contains(uniqueId)) return;

    if (isNewOrderNotification(data)) {
      final orderTitle =
          notification?.title ?? data['title']?.toString() ?? 'New Order';
      final orderBody =
          notification?.body ??
          data['body']?.toString() ??
          'You have a new delivery order';

      await showOrderNotification(
        title: orderTitle,
        body: orderBody,
        payload: jsonEncode(data),
        notificationId: uniqueId,
        orderData: data,
      );

      _markNotificationShown(uniqueId);
      return;
    }

    if (Platform.isIOS && notification != null) {
      debugPrint(
        '📱 iOS automatically presents FCM notification payload via setForegroundNotificationPresentationOptions. Skipping duplicate local notification display.',
      );
      _markNotificationShown(uniqueId);
      return;
    }

    final silentTitle = NotificationPayloadUtil.titleFrom(message, data);
    final silentBody = NotificationPayloadUtil.bodyFrom(message, data);
    if (silentTitle.isEmpty && silentBody.isEmpty) return;

    if (!_isInitialized) await initialize();

    await showSimpleNotification(
      title: silentTitle.isNotEmpty ? silentTitle : silentBody,
      body: silentTitle.isNotEmpty ? silentBody : '',
      payload: jsonEncode(data),
      notificationId: uniqueId,
    );
    _markNotificationShown(uniqueId);
  }

  void _markNotificationShown(String uniqueId) {
    _shownNotificationIds.add(uniqueId);
    _notificationTimestamps[uniqueId] = DateTime.now();
  }

  void _cleanOldNotificationIds() {
    final now = DateTime.now();
    final keysToRemove = <String>[];
    _notificationTimestamps.forEach((id, timestamp) {
      if (now.difference(timestamp).inMinutes > 5) {
        keysToRemove.add(id);
      }
    });
    for (final id in keysToRemove) {
      _shownNotificationIds.remove(id);
      _notificationTimestamps.remove(id);
    }
  }

  Future<String?> getFCMToken() async {
    if (_firebaseMessaging == null) await _initializeFirebaseMessaging();
    if (Platform.isIOS) {
      try {
        String? apnsToken = await _firebaseMessaging?.getAPNSToken();
        if (apnsToken == null) {
          debugPrint('📱 APNs Token is null, waiting for APNs registration...');
          await Future.delayed(const Duration(seconds: 2));
          apnsToken = await _firebaseMessaging?.getAPNSToken();
        }
        debugPrint('📱 APNs Token: $apnsToken');
      } catch (e) {
        debugPrint('⚠️ Error fetching APNs token: $e');
      }
    }
    return await _firebaseMessaging?.getToken();
  }

  /// Save FCM token to backend API
  Future<bool> saveFCMTokenToBackend({
    String? phone,
    String? platform,
    String? appRole,
  }) async {
    try {
      if (PrefsUtil.getAccessToken() == null) return false;
      final token = await getFCMToken();
      if (token == null || token.isEmpty) return false;
      return await ApiService().saveFCMToken(
        token: token,
        phone: phone ?? PrefsUtil.getPhoneNumber(),
        platform: platform,
        appRole: appRole ?? AppConfig.appRole,
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> _createNotificationChannel() async {
    try {
      const AndroidNotificationChannel standardChannel =
          AndroidNotificationChannel(
            AppConfig.notificationChannelId,
            AppConfig.notificationChannelName,
            description: AppConfig.notificationChannelDescription,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          );

      const AndroidNotificationChannel defaultChannel =
          AndroidNotificationChannel(
            'default',
            'Default',
            description: 'Default phone notifications',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          );

      const AndroidNotificationChannel fallbackChannel =
          AndroidNotificationChannel(
            'fcm_fallback_notification_channel',
            'General Notifications',
            description: 'FCM push notifications',
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
          );

      const AndroidNotificationChannel criticalChannel =
          AndroidNotificationChannel(
            AppConfig.criticalChannelId,
            AppConfig.criticalChannelName,
            description: AppConfig.criticalChannelDescription,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
            showBadge: true,
            enableLights: true,
            ledColor: Colors.red,
          );

      final androidImplementation = _notificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(standardChannel);
        await androidImplementation.createNotificationChannel(defaultChannel);
        await androidImplementation.createNotificationChannel(fallbackChannel);
        await androidImplementation.createNotificationChannel(criticalChannel);
      }
    } catch (e) {
      debugPrint('❌ Error creating notification channel: $e');
    }
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(response.payload!);
        _handleNotificationTap(data);
      } catch (e) {
        _handleNotificationTap({'payload': response.payload});
      }
    } else {
      _handleNotificationTap({});
    }
  }

  void _handleNotificationTap(Map<String, dynamic> data) {
    try {
      _platform.invokeMethod('bringToFront');
    } catch (_) {}
    _tapController.add(data);
  }

  Future<bool> hasNotificationPermission() async {
    if (Platform.isIOS) {
      if (_firebaseMessaging == null) {
        _firebaseMessaging = FirebaseMessaging.instance;
      }
      final settings = await _firebaseMessaging!.getNotificationSettings();
      final isAuthorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      if (isAuthorized) return true;
    }
    final status = await Permission.notification.status;
    return status.isGranted || status.isProvisional;
  }

  Future<bool> requestPermission() async {
    try {
      if (Platform.isIOS) {
        if (_firebaseMessaging == null) {
          _firebaseMessaging = FirebaseMessaging.instance;
        }
        final settings = await _firebaseMessaging!.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );
        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          return true;
        }
      }
      final currentStatus = await Permission.notification.status;
      if (currentStatus.isGranted || currentStatus.isProvisional) return true;
      final status = await Permission.notification.request();
      return status.isGranted || status.isProvisional;
    } catch (e) {
      debugPrint('❌ Error requesting notification permission: $e');
      return false;
    }
  }

  Future<void> showSimpleNotification({
    required String title,
    required String body,
    String? payload,
    String? notificationId,
  }) async {
    final int localNotificationId =
        notificationId != null && notificationId.isNotEmpty
        ? notificationId.hashCode.abs() % 2147483647
        : '${title}_$body'.hashCode.abs() % 2147483647;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          AppConfig.notificationChannelId,
          AppConfig.notificationChannelName,
          channelDescription: AppConfig.notificationChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          icon: AppConfig.notificationIcon,
          showWhen: true,
          styleInformation: BigTextStyleInformation(''),
          color: AppConfig.notificationColor,
        );

    await _notificationsPlugin.show(
      localNotificationId,
      title,
      body,
      const NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  Future<void> showOrderNotification({
    required String title,
    required String body,
    String? payload,
    String? notificationId,
    Map<String, dynamic>? orderData,
  }) async {
    final data = orderData ?? {};
    final localId = NewOrderNotificationUtil.notificationIdFor(data);

    final android = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await NewOrderNotificationUtil.ensureCriticalChannel(android);

    await _notificationsPlugin.show(
      localId,
      title,
      body,
      NewOrderNotificationUtil.buildDetails(),
      payload: payload,
    );
  }

  Future<void> stopOrderAlertSound() async {
    try {
      FlutterBackgroundService().invoke('stopRingtone');
    } catch (_) {}
  }

  /// Cancel all notifications posted by this app (foreground + FCM auto-shown).
  /// Used in the background isolate to remove the Android-auto-displayed notification
  /// before replacing it with the critical-channel version.
  Future<void> cancelAllNotifications() async {
    try {
      await _notificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('⚠️ cancelAllNotifications: $e');
    }
  }
}
