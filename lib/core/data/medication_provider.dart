import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';

part 'medication_provider.g.dart';

class Medication {
  final String id;
  final String assignedTo;
  final String assignedName;
  final String medicationName;
  final String dosage;
  final String frequency;
  final String? instructions;
  final String? doctor;
  final List<String> scheduleTimes; // ["08:00","20:00"]
  final DateTime? startDate;
  final DateTime? endDate;
  final String recurrence; // daily, every_other_day, weekly, monthly, as_needed
  final List<int> daysOfWeek; // 0=Sun..6=Sat (for weekly)
  final bool isActive;

  Medication({
    required this.id,
    required this.assignedTo,
    required this.assignedName,
    required this.medicationName,
    required this.dosage,
    required this.frequency,
    this.instructions,
    this.doctor,
    this.scheduleTimes = const [],
    this.startDate,
    this.endDate,
    this.recurrence = 'daily',
    this.daysOfWeek = const [],
    this.isActive = true,
  });

  factory Medication.fromJson(Map<String, dynamic> json) {
    return Medication(
      id: json['id'] as String,
      assignedTo: json['assigned_to'] as String,
      assignedName: json['assigned_name'] as String,
      medicationName: json['medication_name'] as String,
      dosage: json['dosage'] as String,
      frequency: json['frequency'] as String? ?? 'Daily',
      instructions: json['instructions'] as String?,
      doctor: json['doctor'] as String?,
      scheduleTimes: _parseStringList(json['schedule_times']),
      startDate: json['start_date'] != null
          ? DateTime.tryParse(json['start_date'].toString())
          : null,
      endDate: json['end_date'] != null
          ? DateTime.tryParse(json['end_date'].toString())
          : null,
      recurrence: json['recurrence'] as String? ?? 'daily',
      daysOfWeek: _parseIntList(json['days_of_week']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  static List<String> _parseStringList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => e.toString()).toList();
    return [];
  }

  static List<int> _parseIntList(dynamic val) {
    if (val == null) return [];
    if (val is List) return val.map((e) => (e as num).toInt()).toList();
    return [];
  }

  /// Returns the next scheduled dose time for today, or null if none remaining.
  DateTime? get nextDoseToday {
    if (scheduleTimes.isEmpty) return null;
    final now = DateTime.now();
    for (final t in scheduleTimes) {
      final parts = t.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]) ?? 0;
      final minute = int.tryParse(parts[1]) ?? 0;
      final doseTime = DateTime(now.year, now.month, now.day, hour, minute);
      if (doseTime.isAfter(now)) return doseTime;
    }
    return null;
  }

  /// Human-readable schedule summary
  String get scheduleSummary {
    if (scheduleTimes.isEmpty) return frequency;
    final times = scheduleTimes.map(_formatTimeString).join(', ');
    final recurrenceLabel = _recurrenceLabel;
    return '$recurrenceLabel at $times';
  }

  String get _recurrenceLabel {
    switch (recurrence) {
      case 'daily':
        return 'Daily';
      case 'every_other_day':
        return 'Every Other Day';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      case 'as_needed':
        return 'As Needed';
      default:
        return recurrence;
    }
  }

  static String _formatTimeString(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return time;
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = int.tryParse(parts[1]) ?? 0;
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}

class DoseLog {
  final String id;
  final String medicationId;
  final String userId;
  final String familyId;
  final DateTime scheduledAt;
  final DateTime? takenAt;
  final String status; // pending, taken, missed, skipped
  final String? notes;

  DoseLog({
    required this.id,
    required this.medicationId,
    required this.userId,
    required this.familyId,
    required this.scheduledAt,
    this.takenAt,
    required this.status,
    this.notes,
  });

  factory DoseLog.fromJson(Map<String, dynamic> json) {
    return DoseLog(
      id: json['id'] as String,
      medicationId: json['medication_id'] as String,
      userId: json['user_id'] as String,
      familyId: json['family_id'] as String,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      takenAt: json['taken_at'] != null
          ? DateTime.parse(json['taken_at'] as String)
          : null,
      status: json['status'] as String,
      notes: json['notes'] as String?,
    );
  }
}

@riverpod
Stream<List<Medication>> familyMedications(Ref ref) async* {
  final profile = await ref.watch(currentUserProfileProvider.future);
  if (profile == null) {
    yield [];
    return;
  }

  final supabase = Supabase.instance.client;
  yield* supabase
      .from('medications')
      .stream(primaryKey: ['id'])
      .eq('family_id', profile.familyId)
      .order('created_at', ascending: false)
      .map((events) {
        try {
          print("events");
          print(events);
          return events.map((e) => Medication.fromJson(e)).toList();
        } catch (err) {
          debugPrint('[MedicationProvider] Parse error: $err');
          return <Medication>[];
        }
      });
}

@riverpod
Stream<List<DoseLog>> allDoseLogs(Ref ref) async* {
  final profile = await ref.watch(currentUserProfileProvider.future);
  if (profile == null) {
    yield [];
    return;
  }

  final supabase = Supabase.instance.client;

  yield* supabase
      .from('dose_logs')
      .stream(primaryKey: ['id'])
      .eq('family_id', profile.familyId)
      .order('scheduled_at', ascending: false)
      .map((events) => events.map((e) => DoseLog.fromJson(e)).toList());
}

final allDoseLogsProvider = StreamProvider<List<DoseLog>>((ref) {
  final supabase = Supabase.instance.client;

  return supabase
      .from('dose_logs')
      .stream(primaryKey: ['id'])
      .map((data) => data.map((e) => DoseLog.fromJson(e)).toList());
});
//
// @riverpod
// Stream<List<DoseLog>> doseLogs(Ref ref, String medicationId) async* {
//   final supabase = Supabase.instance.client;
//   yield* supabase
//       .from('dose_logs')
//       .stream(primaryKey: ['id'])
//       .eq('medication_id', medicationId)
//       .order('scheduled_at', ascending: false)
//       .map((events) => events.map((e) => DoseLog.fromJson(e)).toList());
// }
