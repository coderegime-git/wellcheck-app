import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GlobalNotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static RealtimeChannel? _subscription;

  static Future<void> initialize() async {
    if (kIsWeb) return;
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings);

    // Request permissions
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
    debugPrint('[GlobalNotif] Local notifications initialized');
  }

  /// Fire an immediate local notification (e.g., "Welcome to Dashboard")
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (kIsWeb) {
      debugPrint('[Web] Notification bypassed: $title - $body');
      return;
    }
    if (!_initialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      'system_events',
      'System Events',
      channelDescription: 'Realtime updates from your family',
      importance: Importance.max,
      priority: Priority.max,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// Start listening to family `well_events` and fire a local notification on insert.
  static void startListeningForFamilyEvents(String familyId, String myUserId) {
    if (_subscription != null) return; // Already listening

    _subscription = Supabase.instance.client
        .channel('public:well_events')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'well_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'family_id',
            value: familyId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            final eventUserId = newRow['user_id'] as String?;

            // Only notify if someone ELSE did an action
            if (eventUserId != null && eventUserId != myUserId) {
              final title = newRow['title'] as String? ?? 'Family Update';
              final desc = newRow['description'] as String? ?? '';

              // showNotification(
              //   id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
              //   title: title,
              //   body: desc,
              // );
            }
          },
        )
        .subscribe();

    debugPrint('[GlobalNotif] Listening to well_events for family $familyId');
  }

  static Future<void> dispose() async {
    if (_subscription != null) {
      await Supabase.instance.client.removeChannel(_subscription!);
      _subscription = null;
    }
  }
}
