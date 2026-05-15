import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;

/// Handles scheduling and response for check-in notifications.
/// When triggered, the phone rings and shows two action buttons:
///   ✅ I Am Okay   |   🆘 I Need Help
class CheckinNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Notification channel
  static const String _channelId = 'checkin_channel';
  static const String _channelName = 'Check-In Alerts';
  static const String _channelDesc = 'Scheduled check-in reminders';

  // Action identifiers
  static const String actionOkay = 'checkin_okay';
  static const String actionHelp = 'checkin_help';

  // Category identifier (iOS)
  static const String _categoryId = 'checkin_category';

  // Callback hooks — set these from your app so you can react to button taps
  static void Function(String checkinId)? onUserOkay;
  static void Function(String checkinId)? onUserNeedsHelp;

  // ─────────────────────────────────────────────
  // INITIALIZE
  // ─────────────────────────────────────────────

  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;

    // Timezone setup
    tzdata.initializeTimeZones();
    // final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    // final timezoneName = (timezoneInfo as dynamic)?.name as String? ?? 'UTC';
    // tz.setLocalLocation(tz.getLocation(timezoneName));

    // Android setup
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    // iOS setup — register action buttons as a category
    final iosSettings = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          _categoryId,
          actions: [
            DarwinNotificationAction.plain(
              actionOkay,
              '✅ I Am Okay',
              options: {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              actionHelp,
              '🆘 I Need Help',
              options: {
                DarwinNotificationActionOption.foreground,
                DarwinNotificationActionOption.destructive,
              },
            ),
          ],
          options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
      ],
    );

    await _plugin.initialize(
      InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: _onNotificationResponse,
    );

    // Android: create the notification channel
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );

    // iOS: request permissions
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
    debugPrint('[CheckinNotif] Initialized');
  }

  // ─────────────────────────────────────────────
  // SCHEDULE A CHECK-IN
  // ─────────────────────────────────────────────

  /// Schedule a one-time check-in notification.
  /// [schedule] must contain:
  ///   - 'id'            : unique identifier (String or int)
  ///   - 'checkin_date'  : ISO date string, e.g. "2025-06-01"
  ///   - 'checkin_time'  : "HH:mm" string, e.g. "14:30"
  static Future<void> scheduleCheckin(Map<String, dynamic> schedule) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();

    // Parse date + time
    final date = DateTime.parse(schedule['checkin_date'] as String);
    final timeParts = (schedule['checkin_time'] as String).split(':');
    if (timeParts.length < 2) {
      debugPrint('[CheckinNotif] Invalid checkin_time format');
      return;
    }

    final scheduledLocal = tz.TZDateTime(
      tz.local,
      date.year,
      date.month,
      date.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    // Don't schedule in the past
    if (scheduledLocal.isBefore(tz.TZDateTime.now(tz.local))) {
      debugPrint(
        '[CheckinNotif] Skipping — time is in the past: $scheduledLocal',
      );
      return;
    }

    final notifId = schedule['id'].toString().hashCode.abs() % 2147483647;
    final payload = schedule['id'].toString();

    await _plugin.zonedSchedule(
      notifId,
      '🔔 Check-In Time',
      'Please let us know how you are doing.',
      scheduledLocal,
      _buildNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );

    debugPrint('[CheckinNotif] Scheduled id=$notifId for $scheduledLocal');
  }

  // ─────────────────────────────────────────────
  // SHOW IMMEDIATELY (for testing / instant alert)
  // ─────────────────────────────────────────────

  static Future<void> showCheckinNow({
    required String checkinId,
    String title = '🔔 Check-In Time',
    String body = 'Please let us know how you are doing.',
  }) async {
    if (kIsWeb) return;
    if (!_initialized) await initialize();

    final notifId = checkinId.hashCode.abs() % 2147483647;

    await _plugin.show(
      notifId,
      title,
      body,
      _buildNotificationDetails(),
      payload: checkinId,
    );

    debugPrint('[CheckinNotif] Shown immediately id=$notifId');
  }

  // ─────────────────────────────────────────────
  // CANCEL
  // ─────────────────────────────────────────────

  static Future<void> cancelCheckin(String checkinId) async {
    final notifId = checkinId.hashCode.abs() % 2147483647;
    await _plugin.cancel(notifId);
    debugPrint('[CheckinNotif] Cancelled id=$notifId');
  }

  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
    debugPrint('[CheckinNotif] All cancelled');
  }

  // ─────────────────────────────────────────────
  // INTERNAL — notification details with action buttons
  // ─────────────────────────────────────────────

  static NotificationDetails _buildNotificationDetails() {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      // phone rings / wakes screen
      enableVibration: true,
      playSound: true,
      icon: '@mipmap/ic_launcher',
      actions: [
        AndroidNotificationAction(
          actionOkay,
          '✅ I Am Okay',
          showsUserInterface: true, // brings app to foreground on tap
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          actionHelp,
          '🆘 I Need Help',
          showsUserInterface: true,
          cancelNotification: true,
        ),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: _categoryId,
    );

    return const NotificationDetails(android: androidDetails, iOS: iosDetails);
  }

  // ─────────────────────────────────────────────
  // RESPONSE HANDLER
  // ─────────────────────────────────────────────

  @pragma('vm:entry-point')
  static void _onNotificationResponse(NotificationResponse response) {
    final checkinId = response.payload ?? '';
    debugPrint(
      '[CheckinNotif] Response — action: ${response.actionId}, checkinId: $checkinId',
    );

    switch (response.actionId) {
      case actionOkay:
        debugPrint('[CheckinNotif] User is OKAY — checkinId: $checkinId');
        onUserOkay?.call(checkinId);
        break;

      case actionHelp:
        debugPrint('[CheckinNotif] User NEEDS HELP — checkinId: $checkinId');
        onUserNeedsHelp?.call(checkinId);
        break;

      default:
        // User tapped the notification body itself (no action button)
        // Treat as opening the app — you can navigate here
        debugPrint(
          '[CheckinNotif] Notification body tapped — checkinId: $checkinId',
        );
        break;
    }
  }
}
