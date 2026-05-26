// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
//
// /// Background message handler — must be a top-level function.
// @pragma('vm:entry-point')
// Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
//   await Firebase.initializeApp();
//   debugPrint('[FCM Background] ${message.notification?.title}');
// }
//
// /// Push notification service for Well-Check.
// /// Handles Firebase Cloud Messaging setup, permissions, and token management.
// class PushNotificationService {
//   static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
//
//   /// Initialize FCM: request permissions, get token, store to Supabase profile.
//   static Future<void> initialize() async {
//     // Request permission (iOS requires explicit ask)
//     final settings = await _messaging.requestPermission(
//       alert: true,
//       badge: true,
//       sound: true,
//       criticalAlert: true, // For SOS alerts
//     );
//
//     debugPrint('[FCM] Permission: ${settings.authorizationStatus}');
//
//     if (settings.authorizationStatus == AuthorizationStatus.authorized ||
//         settings.authorizationStatus == AuthorizationStatus.provisional) {
//       // Get FCM token
//       final token = await _messaging.getToken();
//       debugPrint('[FCM] Token: $token');
//
//       // Save token to Supabase profile for server-side push targeting
//       if (token != null) {
//         await _saveTokenToProfile(token);
//       }
//
//       // Listen for token refresh
//       _messaging.onTokenRefresh.listen(_saveTokenToProfile);
//
//       // Handle foreground messages
//       FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
//
//       // Handle background message tap (app was in background, user tapped notification)
//       FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
//     }
//
//     // Set background handler
//     FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);
//
//     // Check if app was opened from a terminated state via notification
//     final initialMessage = await _messaging.getInitialMessage();
//     if (initialMessage != null) {
//       _handleMessageOpenedApp(initialMessage);
//     }
//   }
//
//   /// Save FCM token to the user's Supabase profile for targeted push.
//   static Future<void> _saveTokenToProfile(String token) async {
//     try {
//       final user = Supabase.instance.client.auth.currentUser;
//       if (user == null) return;
//
//       await Supabase.instance.client
//           .from('profiles')
//           .update({'fcm_token': token})
//           .eq('id', user.id);
//
//       debugPrint('[FCM] Token saved to profile.');
//     } catch (e) {
//       debugPrint('[FCM] Error saving token: $e');
//     }
//   }
//
//   /// Handle foreground push messages — show in-app notification.
//   static void _handleForegroundMessage(RemoteMessage message) {
//     debugPrint(
//       '[FCM Foreground] ${message.notification?.title}: ${message.notification?.body}',
//     );
//     // The GlobalAlertOverlay will handle SOS-type notifications via Supabase Realtime.
//     // This handler is for secondary notifications like medication reminders.
//   }
//
//   /// Handle notification tap when app was in background/terminated.
//   static void _handleMessageOpenedApp(RemoteMessage message) {
//     debugPrint('[FCM Opened] ${message.data}');
//     // Future: navigate to the relevant screen based on message.data['type']
//   }
// }
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'checkin_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();

  final action = message.data['action'];

  if (action == 'schedule_checkin') {
    final scheduleString = message.data['schedule'];
    if (scheduleString != null) {
      final schedule = jsonDecode(scheduleString) as Map<String, dynamic>;
      // ── This runs on User B's device and schedules locally ──
      await CheckinNotificationService.initialize();
      await CheckinNotificationService.scheduleCheckin(schedule);
    }
  }
}

class PushNotificationService extends ConsumerStatefulWidget {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Channel for normal notifications
  static const AndroidNotificationChannel _generalChannel =
      AndroidNotificationChannel(
        'general_channel',
        'General Notifications',
        description: 'General app notifications',
        importance: Importance.high,
        sound: RawResourceAndroidNotificationSound('custom_sound'),
      );

  // Channel for SOS/urgent alerts
  static const AndroidNotificationChannel _sosChannel =
      AndroidNotificationChannel(
        'sos_channel',
        'SOS Alerts',
        description: 'Emergency and SOS alerts',
        importance: Importance.max,
        enableVibration: true,
        playSound: true,
        sound: RawResourceAndroidNotificationSound('sos_sound'),
      );

  static Future<void> initialize() async {
    tz.initializeTimeZones();
    // final String timezoneName = await FlutterTimezone.getLocalTimezone();
    // tz.setLocalLocation(tz.getLocation(timezoneName));
    // Step 1: Request FCM permission
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      criticalAlert: true,
    );
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, // ← don't show FCM notification natively on iOS
      badge: true,
      sound: true,
    );
    debugPrint('[FCM] Permission: ${settings.authorizationStatus}');

    // Step 2: Setup local notifications
    await _setupLocalNotifications();

    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Get and save FCM token
      final token = await _messaging.getToken();
      final apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      print("APNS Token: $apnsToken");

      final fcmToken = await FirebaseMessaging.instance.getToken();
      debugPrint('[FCM] fcmToken: $token');
      print(token);
      if (token != null) await _saveTokenToProfile(token);

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_saveTokenToProfile);

      // Handle foreground messages — show local notification
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap from background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);
    }

    // Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    // App opened from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleMessageOpenedApp(initialMessage);
    }
  }

  static Future<void> _setupLocalNotifications() async {
    // Android initialization
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/launcher_icon',
    );

    // iOS initialization
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create Android notification channels
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(_generalChannel);
    await androidPlugin?.createNotificationChannel(_sosChannel);
    await androidPlugin?.createNotificationChannel(_checkinChannel);
  }

  static const AndroidNotificationChannel _checkinChannel =
      AndroidNotificationChannel(
        'checkin_channel',
        'Check-In Alerts',
        description: 'Scheduled check-in reminders',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        sound: RawResourceAndroidNotificationSound('custom_sound'),
      );

  static void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[LocalNotif] Tapped: ${response.payload}');
    // TODO: navigate based on payload
  }

  static void _handleForegroundMessage(RemoteMessage message) async {
    debugPrint(
      '[FCM Foreground] ${message.notification?.title}: ${message.notification?.body}',
    );
    debugPrint('[FCM Foreground] ${message}');

    final notification = message.notification;
    if (notification == null) return;
    final action = message.data['action'];
    print("cccc");

    // if (action == 'schedule_checkin') {
    //   print("aaaaaaa");
    //   final scheduleString = message.data['schedule'];
    //
    //   if (scheduleString != null && scheduleString.isNotEmpty) {
    //     final schedule = jsonDecode(scheduleString) as Map<String, dynamic>;
    //     print("bbbbb");
    //
    //     await PushNotificationService.scheduleCheckinNotification(schedule);
    //   }
    // }
    // Determine if SOS alert
    final isSos =
        message.data['type'] == 'sos' ||
        (notification.title?.toLowerCase().contains('sos') ?? false) ||
        (notification.title?.toLowerCase().contains('emergency') ?? false);
    final sound = message.data['sound'];

    //final isSos = sound == "sos_sound";
    showNotification(
      title: notification.title ?? 'Well-Check',
      body: notification.body ?? '',
      payload: message.data.toString(),
      isSos: isSos,
      sound: sound,
    );
  }

  static void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM Opened] ${message.data}');
    // TODO: navigate to relevant screen based on message.data['type']
  }

  /// Call this anywhere to show a local notification manually
  static Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String? sound,
    bool isSos = false,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      isSos ? _sosChannel.id : _generalChannel.id,
      isSos ? _sosChannel.name : _generalChannel.name,
      channelDescription: isSos
          ? _sosChannel.description
          : _generalChannel.description,
      importance: isSos ? Importance.max : Importance.high,
      priority: isSos ? Priority.max : Priority.high,
      sound: isSos
          ? RawResourceAndroidNotificationSound(sound ?? "custom_sound")
          : null,
      // color: isSos ? const Color(0xFFFF3B30) : Colors.white,
      enableLights: true,
      enableVibration: true,
      icon: '@mipmap/launcher_icon',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
      styleInformation: BigTextStyleInformation(body),
      // Full screen intent for SOS
      fullScreenIntent: isSos,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: sound,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> _saveTokenToProfile(String token) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', user.id);
      debugPrint('[FCM] Token saved to profile.');
    } catch (e) {
      debugPrint('[FCM] Error saving token: $e');
    }
  }

  /// Show a notification from anywhere in the app
  static Future<void> showSosAlert({
    required String memberName,
    required String message,
  }) async {
    await showNotification(
      title: '🚨 SOS Alert — $memberName',
      body: message,
      isSos: true,
    );
  }

  static Future<void> showCareReminder({
    required String title,
    required String body,
  }) async {
    await showNotification(title: title, body: body, isSos: false);
  }

  static Future<void> scheduleCheckinNotification(
    Map<String, dynamic> schedule,
  ) async {
    final date = DateTime.parse(schedule['checkin_date']);
    print("cccccc");

    final time = schedule['checkin_time'].toString().split(':');

    final scheduledDate = DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(time[0]),
      int.parse(time[1]),
    );

    final tzScheduled = tz.TZDateTime.from(scheduledDate, tz.local);
    if (tzScheduled.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint(
        '[Checkin] Skipping — scheduled time is in the past: $tzScheduled',
      );
      return;
    }

    // await _localNotifications.zonedSchedule(
    //   schedule['id'].hashCode,
    //   'Time to Check In',
    //   'Please confirm you are okay',
    //   tz.TZDateTime.from(scheduledDate, tz.local),
    //   const NotificationDetails(
    //     android: AndroidNotificationDetails(
    //       'checkin_channel',
    //       'Check-In Alerts',
    //       channelDescription: 'Scheduled check-in reminders',
    //       importance: Importance.max,
    //       priority: Priority.high,
    //       fullScreenIntent: true,
    //     ),
    //     iOS: DarwinNotificationDetails(
    //       presentAlert: true,
    //       presentBadge: true,
    //       presentSound: true,
    //     ),
    //   ),
    //   androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    //   uiLocalNotificationDateInterpretation:
    //       UILocalNotificationDateInterpretation.absoluteTime,
    // );
    await _localNotifications.zonedSchedule(
      schedule['id'].toString().hashCode.abs(),
      'Time to Check In',
      'Please confirm you are okay',
      tzScheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'checkin_channel',
          'Check-In Alerts',
          channelDescription: 'Scheduled check-in reminders',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // ← changed
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // no matchDateTimeComponents — check-in is a one-time alarm, not daily repeat
    );
  }

  @override
  ConsumerState<ConsumerStatefulWidget> createState() {
    // TODO: implement createState
    throw UnimplementedError();
  }
}
