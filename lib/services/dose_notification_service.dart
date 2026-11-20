import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class DoseNotificationService {
  DoseNotificationService._();

  static final instance = DoseNotificationService._();

  static const _countdownMinutes = 15;
  static const _slots = 7; // how many upcoming doses to schedule
  static const _missedGraceMinutes = 5;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  static const _maxPending = 60; // iOS cap is 64, leave headroom
  static const _missedRepeats = 20; // reminders after the dose time

  int _repeatId(String medId, int r) =>
      10000000 + (medId.hashCode.abs() % 100000) * 100 + r;
  static const _actionLog = 'dose_log';
  static const _actionSkip = 'dose_skip';
  static const _iosCategory = 'dose_actions';

  /// Set this from your app (see step 5)
  Future<void> Function(String medId, String action)? onAction;
  (String, String)? _pendingAction;

  // Future<void> syncMine(List<dynamic> myMeds) async {
  //   await init();
  //   await _plugin
  //       .cancelAll(); // or cancelMedication(id) per med if you have other notifications
  //   final now = DateTime.now();
  //   final mode = await _scheduleMode();
  //
  //   final doses = <({String id, String name, String dosage, DateTime at})>[];
  //   for (final m in myMeds) {
  //     final DateTime? next = m.nextDoseToday;
  //     if (next == null || !next.isAfter(now)) continue;
  //     doses.add((
  //       id: m.id as String,
  //       name: m.medicationName as String,
  //       dosage: '${m.dosage}',
  //       at: next.toLocal(),
  //     ));
  //   }
  //   doses.sort((a, b) => a.at.compareTo(b.at));
  //
  //   // // 2 notifications per dose
  //   // for (final d in doses.take(_maxPending ~/ (1 + _missedRepeats))) {
  //   //   await _scheduleDose(
  //   //     medId: d.id,
  //   //     name: d.name,
  //   //     dosage: d.dosage,
  //   //     dose: d.at,
  //   //     slot: 0,
  //   //     mode: mode,
  //   //   );
  //   // }
  //   for (final d in doses.take(
  //     _maxPending ~/ (1 + _missedRepeats + _countdownMinutes),
  //   )) {
  //     await _scheduleDose(
  //       medId: d.id,
  //       name: d.name,
  //       dosage: d.dosage,
  //       dose: d.at,
  //       slot: 0,
  //       mode: mode,
  //     );
  //   }
  //
  //   final pending = await _plugin.pendingNotificationRequests();
  //   debugPrint('[DoseSync] count=${pending.length}');
  // }
  Future<void> reinit() async {
    _ready = false;
    await init();
  }

  Future<List<String>> syncMine(List<dynamic> myMeds) async {
    await init();
    await _plugin.cancelAll();
    final now = DateTime.now();
    final mode = await _scheduleMode();

    final doses = <({String id, String name, String dosage, DateTime at})>[];
    for (final m in myMeds) {
      final DateTime? next = m.nextDoseToday;
      if (next == null || !next.isAfter(now)) continue;
      doses.add((
        id: m.id as String,
        name: m.medicationName as String,
        dosage: '${m.dosage}',
        at: next.toLocal(),
      ));
    }
    doses.sort((a, b) => a.at.compareTo(b.at));

    // final scheduled = <String>[];
    // for (final d in doses.take(
    //   _maxPending ~/ (1 + _missedRepeats + _countdownMinutes),
    // )) {
    //   await _scheduleDose(
    //     medId: d.id,
    //     name: d.name,
    //     dosage: d.dosage,
    //     dose: d.at,
    //     slot: 0,
    //     mode: mode,
    //   );
    //   scheduled.add(d.id);
    //   try {
    //     await Supabase.instance.client
    //         .from('medications')
    //         .update({'is_synced': true})
    //         .eq('id', d.id);
    //   } catch (e) {
    //     debugPrint('[DoseSync] mark synced failed for ${d.id}: $e');
    //   }
    // }
    final scheduled = <String>[];
    var budget = _maxPending;
    for (var i = 0; i < doses.length; i++) {
      final d = doses[i];
      final repeats = i == 0
          ? 30
          : 3; // nearest dose gets 30 minutes of reminders
      final cost = 1 + _countdownMinutes + repeats;
      if (cost > budget) break;
      budget -= cost;

      await _scheduleDose(
        medId: d.id,
        name: d.name,
        dosage: d.dosage,
        dose: d.at,
        slot: 0,
        mode: mode,
        repeats: repeats,
      );
      scheduled.add(d.id);
      // try {
      //   await Supabase.instance.client
      //       .from('medications')
      //       .update({'is_synced': true})
      //       .eq('id', d.id);
      // } catch (e) {
      //   debugPrint('[DoseSync] mark synced failed for ${d.id}: $e');
      // }
    }
    if (scheduled.isNotEmpty) {
      try {
        final response = await Supabase.instance.client
            .from('medications')
            .update({'is_synced': true})
            .inFilter('id', scheduled.toList())
            .select();

        // final response = await Supabase.instance.client
        //     .from('medications')
        //     .update({'is_synced': true})
        //     .eq('id', scheduled)
        //     .select();
        debugPrint('Updated rows: $response');
        print(scheduled);
      } catch (e) {
        debugPrint('[DoseSync] mark synced failed: $e');
      }
    }
    final pending = await _plugin.pendingNotificationRequests();
    await pruneTray();
    debugPrint('[DoseSync] count=${pending.length}');
    return scheduled;
  }

  Future<void> _scheduleDose({
    required String medId,
    required String name,
    required String dosage,
    required DateTime dose,
    required int slot,
    required AndroidScheduleMode mode,
    int repeats = _missedRepeats,
  }) async {
    final now = DateTime.now();
    final start = dose.subtract(const Duration(minutes: _countdownMinutes));
    final label = dosage.isEmpty ? name : '$name $dosage';
    final body = '$label\nScheduled for ${DateFormat.jm().format(dose)}';

    if (!start.isAfter(now)) {
      await _plugin.show(
        _id(medId, slot),
        'Medication due',
        body,
        _details(dose, body: body, timeout: dose.difference(now), medId: medId),
        payload: medId,
      );
      // } else {
      //   await _plugin.zonedSchedule(
      //     _id(medId, slot),
      //     'Medication due',
      //     body,
      //     tz.TZDateTime.from(start, tz.local),
      //     _details(dose, body: body),
      //     payload: medId,
      //     androidScheduleMode: mode,
      //     uiLocalNotificationDateInterpretation:
      //         UILocalNotificationDateInterpretation.absoluteTime,
      //   );
      // }
    } else if (!Platform.isIOS) {
      // Android only: one notification at T-2 with the ticking countdown
      await _plugin.zonedSchedule(
        _id(medId, slot),
        'Medication due',
        body,
        tz.TZDateTime.from(start, tz.local),
        _details(dose, body: body, medId: medId),
        payload: medId,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    if (Platform.isIOS) {
      for (var m = _countdownMinutes; m >= 1; m--) {
        final at = dose.subtract(Duration(minutes: m));
        if (!at.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          _repeatId(medId, 50 + m),
          'Medication due in $m min',
          body,
          tz.TZDateTime.from(at, tz.local),
          _details(dose, body: body, medId: medId),
          payload: medId,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
    for (var r = 0; r < _missedRepeats; r++) {
      //   final at = dose.add(Duration(minutes: r));
      final at = dose.add(Duration(minutes: _missedGraceMinutes + r));
      await _plugin.zonedSchedule(
        _repeatId(medId, r),
        'Medication missed',
        body,
        tz.TZDateTime.from(at, tz.local),
        _details(at, body: body, missed: true),
        payload: medId,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
    for (var r = 0; r < repeats; r++) {
      // final at = dose.add(Duration(minutes: r));
      final at = dose.add(Duration(minutes: _missedGraceMinutes + r));
      if (!at.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        _repeatId(medId, r),
        'Medication missed',
        body,
        tz.TZDateTime.from(at, tz.local),
        _details(
          at,
          body: body,
          medId: medId,
          missed: true,
          sticky: r == repeats - 1,
        ),
        payload: medId,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  tz.Location _resolveLocation(String id) {
    // Old names that phones still report, mapped to the names the package knows
    const aliases = {
      'Asia/Calcutta': 'Asia/Kolkata',
      'Asia/Saigon': 'Asia/Ho_Chi_Minh',
      'Asia/Katmandu': 'Asia/Kathmandu',
      'Asia/Rangoon': 'Asia/Yangon',
      'Europe/Kiev': 'Europe/Kyiv',
      'America/Buenos_Aires': 'America/Argentina/Buenos_Aires',
      'Atlantic/Faeroe': 'Atlantic/Faroe',
      'Pacific/Samoa': 'Pacific/Pago_Pago',
    };

    for (final name in [id, aliases[id]]) {
      if (name == null) continue;
      try {
        return tz.getLocation(name);
      } catch (_) {}
    }
    return tz.UTC; // last resort
  }

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    // In newer flutter_timezone versions this returns an object: use .identifier
    final zone = await FlutterTimezone.getLocalTimezone();
    //tz.setLocalLocation(tz.getLocation(zone));
    tz.setLocalLocation(_resolveLocation(zone.identifier));
    // await _plugin.initialize(
    //   const InitializationSettings(
    //     android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    //     iOS: DarwinInitializationSettings(
    //       requestAlertPermission: false,
    //       requestBadgePermission: false,
    //       requestSoundPermission: false,
    //     ),
    //   ),
    //   onDidReceiveNotificationResponse: (r) {
    //     // r.payload == medication id. Navigate to the dashboard here if you want.
    //   },
    // );
    await _plugin.initialize(
      InitializationSettings(
        //   android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        android: const AndroidInitializationSettings(
          '@drawable/ic_stat_notification',
        ),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _iosCategory,
              actions: [
                DarwinNotificationAction.plain(
                  _actionLog,
                  'Log',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  _actionSkip,
                  'Skip',
                  options: {DarwinNotificationActionOption.foreground},
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    _ready = true;
  }

  Future<void> debugLog([String tag = '']) async {
    await init();
    final pending = await _plugin.pendingNotificationRequests();
    final active = await _plugin.getActiveNotifications();

    final buf = StringBuffer('[DoseNotif]$tag\n');
    buf.writeln('PENDING (scheduled, not fired yet): ${pending.length}');
    for (final p in pending) {
      buf.writeln('  id=${p.id} | ${p.title} | payload=${p.payload}');
    }
    buf.writeln('ACTIVE (in tray now): ${active.length}');
    for (final a in active) {
      buf.writeln('  id=${a.id} | ${a.title} | channel=${a.channelId}');
    }
    debugPrint(buf.toString());
  }

  Future<void> _onResponse(NotificationResponse r) async {
    final medId = r.payload;
    final action = r.actionId;
    debugPrint('[_onResponse] canExact=${r.id}');
    debugPrint('[_onResponse] canExact=${r.notificationResponseType.name}');
    debugPrint('[_onResponse] canExact=${r.input}');
    debugPrint('[_onResponse] canExact=${r.payload}');

    if (medId == null || (action != _actionLog && action != _actionSkip))
      return;

    if (onAction == null) {
      _pendingAction = (medId, action!);
      return;
    }
    await onAction!(medId, action == _actionLog ? 'log' : 'skip');
  }

  /// Call once after you set onAction (handles a cold start from a button tap)
  Future<void> flushPendingAction() async {
    final p = _pendingAction;
    if (p == null || onAction == null) return;
    _pendingAction = null;
    await onAction!(p.$1, p.$2 == _actionLog ? 'log' : 'skip');
  }

  Future<void> requestPermissions() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();

    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);
  }

  // ---------- ids ----------
  int _id(String medId, int slot) =>
      (medId.hashCode.abs() % 100000) * 100 + slot;

  // ---------- details ----------
  // NotificationDetails _details(DateTime doseLocal) {
  //   return NotificationDetails(
  //     android: AndroidNotificationDetails(
  //       'dose_countdown',
  //       'Dose countdown',
  //       channelDescription: 'Countdown shown before a medication dose',
  //       importance: Importance.high,
  //       priority: Priority.high,
  //       ongoing: true,
  //       autoCancel: false,
  //       usesChronometer: true,
  //       chronometerCountDown: true,
  //       when: doseLocal.millisecondsSinceEpoch,
  //       timeoutAfter: (_countdownMinutes + 1) * 60 * 1000,
  //       category: AndroidNotificationCategory.reminder,
  //     ),
  //     iOS: const DarwinNotificationDetails(
  //       presentAlert: true,
  //       presentSound: true,
  //       interruptionLevel: InterruptionLevel.timeSensitive,
  //     ),
  //   );
  // }
  NotificationDetails _details(
    DateTime dose, {
    required String body,
    bool missed = false,
    bool sticky = false,
    String? medId,
    Duration? timeout,
  }) {
    final color = missed ? const Color(0xFFD32F2F) : const Color(0xFF00796B);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        icon: '@drawable/ic_stat_notification',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/launcher_icon'),
        styleInformation: BigTextStyleInformation(
          body,
          htmlFormatBigText: false,
        ),
        missed ? 'dose_missed' : 'dose_countdown',
        missed ? 'Missed dose' : 'Dose reminder',
        channelDescription: 'Medication reminders',
        importance: Importance.max,
        priority: Priority.max,
        ongoing: true,
        autoCancel: false,
        color: color,
        subText: missed
            ? 'Missed • reminding every 1 min'
            : 'Reminder active • 1 min',
        //styleInformation: BigTextStyleInformation(body),
        // Remove these three lines if you don't want the countdown in the header
        usesChronometer: true,
        chronometerCountDown: !missed,
        when: dose.millisecondsSinceEpoch,
        // timeoutAfter: missed
        //     ? const Duration(hours: 1).inMilliseconds
        //     : (timeout ?? const Duration(minutes: _countdownMinutes))
        //           .inMilliseconds,
        // timeoutAfter: missed
        //     ? const Duration(minutes: 1).inMilliseconds
        //     : (timeout ?? const Duration(minutes: _countdownMinutes))
        //           .inMilliseconds,
        timeoutAfter: sticky
            ? null
            : missed
            ? const Duration(minutes: 1).inMilliseconds
            : (timeout ?? const Duration(minutes: _countdownMinutes))
                  .inMilliseconds,
        category: AndroidNotificationCategory.reminder,
        sound: const RawResourceAndroidNotificationSound('missed_checkin'),
        audioAttributesUsage: AudioAttributesUsage.notification,
        playSound: true,
        enableVibration: true,
        actions: const [
          AndroidNotificationAction(
            _actionLog,
            'Log',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          AndroidNotificationAction(
            _actionSkip,
            'Skip',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
      // iOS: const DarwinNotificationDetails(
      //   presentAlert: true,
      //   presentSound: true,
      //
      //   sound: 'missed_checkin.aiff',
      //   categoryIdentifier: _iosCategory,
      //   interruptionLevel: InterruptionLevel.timeSensitive,
      // ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        sound: 'missed_checkin.aiff',
        categoryIdentifier: _iosCategory,
        threadIdentifier: medId == null ? 'dose' : 'dose_$medId',
        // 'dose_actions'
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    );
  }

  Future<void> pruneTray() async {
    await init();
    final active = await _plugin.getActiveNotifications();

    final missed = active.where((a) => a.title == 'Medication missed').toList()
      ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));

    // remove all missed except the latest
    for (final a in missed.take(missed.isEmpty ? 0 : missed.length - 1)) {
      if (a.id != null) await _plugin.cancel(a.id!);
    }

    // once a missed one exists, the "due" ones are stale
    if (missed.isNotEmpty) {
      for (final a in active) {
        final t = a.title ?? '';
        if (t == 'Medication due' || t.startsWith('Medication due in')) {
          if (a.id != null) await _plugin.cancel(a.id!);
        }
      }
    }
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    var canExact = await android?.canScheduleExactNotifications() ?? false;
    if (!canExact) {
      await android?.requestExactAlarmsPermission();
      canExact = await android?.canScheduleExactNotifications() ?? false;
    }
    debugPrint('[DoseSync] canExact=$canExact');
    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  // ---------- schedule ----------
  Future<void> scheduleMedication({
    required String medId,
    required String name,
    required String dosage,
    required DateTime firstDoseUtc,
    required String recurrence,
    required List<int> daysOfWeek,
  }) async {
    await init();
    await cancelMedication(medId);

    final doses = _occurrences(
      firstDoseUtc.toLocal(),
      recurrence,
      daysOfWeek,
      _slots,
    );
    final now = DateTime.now();
    final mode = await _scheduleMode();

    for (var i = 0; i < doses.length; i++) {
      final dose = doses[i];
      if (!dose.isAfter(now)) continue;

      final start = dose.subtract(const Duration(minutes: _countdownMinutes));
      final timeText = DateFormat.jm().format(dose);
      final label = dosage.isEmpty ? name : '$name $dosage';
      //  final body = '$label\nScheduled for $timeText';
      final body = Platform.isIOS
          ? '$label\nScheduled for ${DateFormat.jm().format(dose)}\nPull down to Log or Skip'
          : '$label\nScheduled for ${DateFormat.jm().format(dose)}';
      if (!start.isAfter(now)) {
        // Already inside the 15-minute window: show right away
        await _plugin.show(
          _id(medId, i),
          'Medication due',
          body,
          _details(
            dose,
            body: body,
            timeout: dose.difference(now),
            medId: medId,
          ),
          payload: medId,
        );
      } else {
        // Appears 15 minutes before the dose
        await _plugin.zonedSchedule(
          _id(medId, i),
          'Medication due',
          body,
          tz.TZDateTime.from(start, tz.local),
          _details(dose, body: body, medId: medId),
          payload: medId,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }

      // Missed state: appears at the dose time (red on Android)
      await _plugin.zonedSchedule(
        _id(medId, 50 + i),
        'Medication missed',
        body,
        //  tz.TZDateTime.from(dose, tz.local),
        tz.TZDateTime.from(
          dose.add(const Duration(minutes: _missedGraceMinutes)),
          tz.local,
        ),
        _details(dose, body: body, missed: true, medId: medId),
        payload: medId,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// Re-sync everything assigned to me (call on app start and when meds change)

  // Future<void> syncMine(List<dynamic> myMeds) async {
  //   await init();
  //   for (final m in myMeds) {
  //     final DateTime? next = m.nextDoseToday;
  //     if (next == null) continue;
  //     await scheduleMedication(
  //       medId: m.id as String,
  //       name: m.medicationName as String,
  //       dosage: '${m.dosage}',
  //       firstDoseUtc: next.toUtc(),
  //       recurrence: 'once',
  //       // unknown value: only this one dose is scheduled
  //       daysOfWeek: const [],
  //     );
  //   }
  //   final pending = await _plugin.pendingNotificationRequests();
  //   debugPrint(
  //     '[DoseSync] pending: ${pending.map((p) => '${p.id}:${p.title}').toList()}',
  //   );
  // }

  // Future<void> cancelMedication(String medId) async {
  //   for (var i = 0; i < _slots; i++) {
  //     await _plugin.cancel(_id(medId, i));
  //   }
  // }
  Future<void> cancelMedication(String medId) async {
    for (var i = 0; i < _slots; i++) {
      await _plugin.cancel(_id(medId, i));
      await _plugin.cancel(_id(medId, 50 + i));
    }
    for (var r = 0; r < _missedRepeats; r++) {
      await _plugin.cancel(_repeatId(medId, r));
    }
    for (var m = 1; m <= _countdownMinutes; m++) {
      await _plugin.cancel(_repeatId(medId, 50 + m));
    }
    for (var r = 0; r < 60; r++) {
      await _plugin.cancel(_repeatId(medId, r));
    }
  }

  // ---------- push payload ----------
  /// Call from FCM foreground and background handlers
  Future<void> handleMessage(Map<String, dynamic> data) async {
    final action = data['action'];
    if (action != 'medication_assigned' && action != 'medication_countdown') {
      return;
    }

    final medId = data['medication_id']?.toString();
    final due = DateTime.tryParse('${data['scheduled_at']}');
    if (medId == null || due == null) return;

    final days = '${data['days_of_week'] ?? ''}'
        .split(',')
        .where((s) => s.isNotEmpty)
        .map(int.parse)
        .toList();

    await scheduleMedication(
      medId: medId,
      name: '${data['medication_name'] ?? 'Medication'}',
      dosage: '${data['dosage'] ?? ''}',
      firstDoseUtc: due,
      recurrence: '${data['recurrence'] ?? 'daily'}',
      daysOfWeek: days,
    );
  }

  // ---------- recurrence (local calendar math, safe across DST) ----------
  List<DateTime> _occurrences(
    DateTime first,
    String recurrence,
    List<int> days,
    int count,
  ) {
    final out = <DateTime>[first];
    var cur = first;

    while (out.length < count) {
      DateTime next;
      switch (recurrence) {
        case 'daily':
          next = DateTime(
            cur.year,
            cur.month,
            cur.day + 1,
            cur.hour,
            cur.minute,
          );
          break;
        case 'every_other_day':
          next = DateTime(
            cur.year,
            cur.month,
            cur.day + 2,
            cur.hour,
            cur.minute,
          );
          break;
        case 'weekly':
          if (days.isEmpty) {
            next = DateTime(
              cur.year,
              cur.month,
              cur.day + 7,
              cur.hour,
              cur.minute,
            );
          } else {
            final sorted = [...days]..sort();
            final wd = cur.weekday % 7; // Sunday = 0
            final nextDay = sorted.firstWhere(
              (d) => d > wd,
              orElse: () => sorted.first + 7,
            );
            next = DateTime(
              cur.year,
              cur.month,
              cur.day + (nextDay - wd),
              cur.hour,
              cur.minute,
            );
          }
          break;
        case 'monthly':
          next = DateTime(
            cur.year,
            cur.month + 1,
            cur.day,
            cur.hour,
            cur.minute,
          );
          break;
        default:
          return out;
      }
      out.add(next);
      cur = next;
    }
    return out;
  }
}
