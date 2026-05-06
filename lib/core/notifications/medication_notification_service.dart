import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:well_check_v3/core/data/medication_provider.dart';

/// Schedules local notifications for medication reminders.
class MedicationNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Initialize the notification plugin. Call once at app start.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;

    tzdata.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final iosCategories = [
      DarwinNotificationCategory(
        'medication_category',
        actions: <DarwinNotificationAction>[
          DarwinNotificationAction.plain('mark_taken', '✓ Mark as Taken'),
          DarwinNotificationAction.plain('snooze', '⏰ Snooze 30 Min'),
        ],
        options: <DarwinNotificationCategoryOption>{
          DarwinNotificationCategoryOption.hiddenPreviewShowTitle,
        },
      )
    ];

    final iosSettings = DarwinInitializationSettings(
      notificationCategories: iosCategories,
    );

    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
       settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTap,
    );

    // Request iOS permissions
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
    debugPrint('[MedNotif] Notification service initialized');
  }

  @pragma('vm:entry-point')
  static void _onNotificationTap(NotificationResponse response) async {
    debugPrint('[MedNotif] Tapped: ${response.payload}, Action: ${response.actionId}');
    if (response.actionId == 'mark_taken' && response.payload != null) {
      // In a real app, you would initialize Supabase here if it's not already,
      // and insert into 'dose_logs'. Example placeholder:
      debugPrint('[MedNotif] Mark taken triggered for med_id: ${response.payload}');
    }
  }

  /// Schedule notifications for all active medications.
  /// Call this after saving/editing/deleting a medication.
  static Future<void> scheduleForMedications(
      List<Medication> medications) async {
    if (kIsWeb) {
      debugPrint('[Web] Medication Notifications bypassed');
      return;
    }
    if (!_initialized) await initialize();

    // Cancel all existing medication notifications
    await cancelAll();

    int notifId = 1000;

    for (final med in medications) {
      if (!med.isActive || med.scheduleTimes.isEmpty) continue;
      if (med.recurrence == 'as_needed') continue;

      for (final timeStr in med.scheduleTimes) {
        final parts = timeStr.split(':');
        if (parts.length != 2) continue;

        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = int.tryParse(parts[1]) ?? 0;

        await _scheduleDailyNotification(
          id: notifId++,
          title: '💊 Time for ${med.medicationName}',
          body: '${med.dosage} — ${med.instructions ?? 'Take as prescribed'}',
          hour: hour,
          minute: minute,
          payload: med.id,
        );
      }
    }

    debugPrint(
        '[MedNotif] Scheduled ${notifId - 1000} notifications for ${medications.length} medications');
  }

  static Future<void> _scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    // If the time has already passed today, schedule for tomorrow
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'medication_reminders',
      'Medication Reminders',
      channelDescription: 'Reminders to take your medications',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('mark_taken', '✓ Mark as Taken'),
        AndroidNotificationAction('snooze', '⏰ Snooze 30 Min'),
      ],
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      categoryIdentifier: 'medication_category',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.zonedSchedule(
       id,
       title,
       body,
       scheduledDate,
    details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: payload, uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  /// Cancel all medication notifications.
  static Future<void> cancelAll() async {
    if (kIsWeb) return;
    await _plugin.cancelAll();
  }
}
