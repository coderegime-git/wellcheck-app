import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:live_activities/live_activities.dart';

class DoseLiveActivityService {
  DoseLiveActivityService._();

  static final instance = DoseLiveActivityService._();

  //static const _appGroup = 'group.com.app.wellcheck';
  static const _appGroup = 'group.com.app.wellcheck';
  final _la = LiveActivities();
  bool _ready = false;
  static const leadMinutes = 7 * 60;
  final Map<String, Timer> _timers = {};

  Future<void> _start(
    String medId,
    String name,
    String dosage,
    DateTime next,
  ) async {
    final now = DateTime.now();
    if (!next.isAfter(now)) return;
    final id = await _la.createActivity(
      'dose_$medId',
      _data(name, dosage, next),
      removeWhenAppIsKilled: false,
      staleIn: next.difference(now),
    );
    debugPrint('[LiveActivity] created=$id for $medId');
  }

  Future<bool> _prepare() async {
    if (!Platform.isIOS) return false;
    if (!_ready) {
      await _la.init(appGroupId: _appGroup);
      _ready = true;
    }
    return _la.areActivitiesEnabled();
  }

  Map<String, dynamic> _data(String name, String dosage, DateTime dose) => {
    'name': name,
    'dosage': dosage,
    'doseAtMs': dose.millisecondsSinceEpoch.toString(),
    // string avoids type issues
  };

  /// Start a countdown for every medication whose next dose is inside the window
  // Future<void> sync(List<dynamic> myMeds, {int windowMinutes = 180}) async {
  //   if (!await _prepare()) return;
  //
  //   await _la.endAllActivities();
  //
  //   final now = DateTime.now();
  //   for (final m in myMeds) {
  //     final DateTime? next = (m.nextDoseToday as DateTime?)?.toLocal();
  //     if (next == null || !next.isAfter(now)) continue;
  //     if (next.difference(now).inMinutes > windowMinutes) continue;
  //
  //     // final id = await _la.createActivity(
  //     //   'dose_${m.id}',
  //     //   _data('${m.medicationName}', '${m.dosage}', next),
  //     //   staleIn: next.difference(now),
  //     // );
  //     final local = next.toLocal();
  //     debugPrint(
  //       '[LiveActivity] next=$local now=$now diff=${local.difference(now)}',
  //     );
  //
  //     final id = await _la.createActivity(
  //       'dose_${m.id}',
  //       _data('${m.medicationName}', '${m.dosage}', local),
  //       staleIn: local.difference(now),
  //     );
  //     debugPrint('[LiveActivity] created=$id for ${m.id}');
  //   }
  // }

  //Live
  // Future<void> sync(List<dynamic> myMeds) async {
  //   if (!await _prepare()) return;
  //
  //   for (final t in _timers.values) {
  //     t.cancel();
  //   }
  //   _timers.clear();
  //   await _la.endAllActivities();
  //
  //   final now = DateTime.now();
  //   for (final m in myMeds) {
  //     final DateTime? next = (m.nextDoseToday as DateTime?)?.toLocal();
  //     if (next == null || !next.isAfter(now)) continue;
  //
  //     final medId = m.id as String;
  //     final name = '${m.medicationName}';
  //     final dosage = '${m.dosage}';
  //     final start = next.subtract(const Duration(minutes: leadMinutes));
  //
  //     if (!start.isAfter(now)) {
  //       // already inside the lead window: start now
  //       await _start(medId, name, dosage, next);
  //     } else {
  //       // start automatically at T - leadMinutes
  //       _timers[medId] = Timer(start.difference(now), () {
  //         _start(medId, name, dosage, next);
  //       });
  //     }
  //   }
  // }
  Future<void> sync(
    List<dynamic> myMeds, {
    bool Function(dynamic med)? isTakenToday,
  }) async {
    if (!await _prepare()) return;

    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    await _la.endAllActivities();

    for (final m in myMeds) {
      _schedule(m, takenToday: isTakenToday?.call(m) ?? false);
    }
  }

  final Map<String, DateTime> _handledDay = {};

  /// Call after taken / not taken so the countdown moves to the next occurrence
  // Future<void> reschedule(dynamic m, {bool takenToday = true}) async {
  //   await end(m.id as String);
  //   if (!await _prepare()) return;
  //   _schedule(m, takenToday: takenToday);
  // }
  Future<void> reschedule(dynamic m, {bool takenToday = true}) async {
    final id = m.id as String;
    if (takenToday) _handledDay[id] = DateTime.now();
    await end(id);
    if (!await _prepare()) return;
    _schedule(m, takenToday: takenToday);
  }

  void _schedule(dynamic m, {required bool takenToday}) {
    final now = DateTime.now();
    final h = _handledDay[m.id as String];
    if (h != null &&
        h.year == now.year &&
        h.month == now.month &&
        h.day == now.day) {
      takenToday = true;
    }
    // final now = DateTime.now();
    final List<String> times = List<String>.from(m.scheduleTimes ?? <String>[]);

    final DateTime? next = times.isNotEmpty
        ? DoseSchedule.nextDose(
            scheduleTimes: times,
            recurrence: '${m.recurrence ?? 'daily'}',
            frequency: '${m.frequency ?? ''}',
            daysOfWeek: (m.daysOfWeek as List?)?.cast<int>(),
            startDate: (m.startDate as DateTime?) ?? now,
            // use your startDate source
            isTakenToday: takenToday,
            now: now,
          )
        : (m.nextDoseToday as DateTime?)
              ?.toLocal(); // fallback to old behaviour

    if (next == null || !next.isAfter(now)) return;

    final medId = m.id as String;
    final name = '${m.medicationName}';
    final dosage = '${m.dosage}';
    final start = next.subtract(const Duration(minutes: leadMinutes));

    if (!start.isAfter(now)) {
      _start(medId, name, dosage, next);
    } else {
      _timers[medId]?.cancel();
      _timers[medId] = Timer(start.difference(now), () {
        _start(medId, name, dosage, next);
      });
    }
  }

  // Future<void> end(String medId) async {
  //   if (!await _prepare()) return;
  //   await _la.endActivity('dose_$medId');
  // }
  Future<void> end(String medId) async {
    _timers.remove(medId)?.cancel();
    if (!await _prepare()) return;
    await _la.endActivity('dose_$medId');
  }

  /// Demo: countdown for a fake dose, no medication needed
  Future<void> demo({int minutes = 2}) async {
    if (!await _prepare()) return;
    final dose = DateTime.now().add(Duration(minutes: minutes));
    await _la.createActivity(
      'dose_demo',
      _data('Lexapro', '10mg', dose),
      staleIn: Duration(minutes: minutes),
    );
  }
}

class DoseSchedule {
  /// Next dose >= now (or >= tomorrow 00:00 if today's dose is already taken).
  /// daysOfWeek uses Sunday = 0 ... Saturday = 6, same as the cron.
  static DateTime? nextDose({
    required List<String> scheduleTimes,
    required String recurrence,
    required String frequency,
    required DateTime startDate,
    List<int>? daysOfWeek,
    bool isTakenToday = false,
    DateTime? now,
  }) {
    now ??= DateTime.now();
    final freq = frequency.toLowerCase();
    if (freq.contains('as needed')) return null;

    final kind = freq.contains('weekly') ? 'weekly' : recurrence;
    final cutoff = isTakenToday
        ? DateTime(now.year, now.month, now.day + 1)
        : now;
    final startDay = DateTime(startDate.year, startDate.month, startDate.day);
    final weekDays = (daysOfWeek == null || daysOfWeek.isEmpty)
        ? <int>{startDate.weekday % 7}
        : daysOfWeek.toSet();

    DateTime? best;
    for (final t in scheduleTimes) {
      final parts = t.split(':');
      if (parts.length < 2) continue;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) continue;

      for (var i = 0; i < 400; i++) {
        // DateTime() normalizes overflow and is DST-safe (unlike add(Duration))
        final c = DateTime(cutoff.year, cutoff.month, cutoff.day + i, h, m);
        if (c.isBefore(cutoff)) continue;
        final day = DateTime(c.year, c.month, c.day);
        if (day.isBefore(startDay)) continue;

        final ok = switch (kind) {
          'every_other_day' =>
            DateTime.utc(day.year, day.month, day.day)
                        .difference(
                          DateTime.utc(
                            startDay.year,
                            startDay.month,
                            startDay.day,
                          ),
                        )
                        .inDays %
                    2 ==
                0,
          'weekly' => weekDays.contains(c.weekday % 7),
          'monthly' => c.day == startDate.day,
          _ => true, // daily
        };
        if (!ok) continue;

        if (best == null || c.isBefore(best)) best = c;
        break;
      }
    }
    return best;
  }
}
