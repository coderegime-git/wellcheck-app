// import 'package:battery_plus/battery_plus.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:well_check_v3/core/design/shield_theme.dart';
// import 'package:well_check_v3/core/data/user_profile_provider.dart';
// import 'package:well_check_v3/core/data/medication_provider.dart';
// import 'package:intl/intl.dart';
//
// import '../../../main.dart';
//
// class PendingActionsCard extends ConsumerWidget {
//   const PendingActionsCard({super.key});
//
//   Future<void> _logDose(
//     BuildContext context,
//     WidgetRef ref,
//     Medication med,
//     String userId,
//     String familyId,
//   ) async {
//     final now = DateTime.now().toUtc();
//     try {
//       await Supabase.instance.client.from('dose_logs').insert({
//         'medication_id': med.id,
//         'user_id': userId,
//         'family_id': familyId,
//         'scheduled_at': now.toIso8601String(),
//         'taken_at': now.toIso8601String(),
//         'status': 'taken',
//       });
//       int batteryLevel =
//           100; // Safe default for simulators and aggressive background iOS policies
//       try {
//         final battery = Battery();
//         batteryLevel = await battery.batteryLevel;
//       } catch (e) {
//         debugPrint(
//           'Battery info not available over isolate, using default: $e',
//         );
//       }
//       final profile = await ref.read(currentUserProfileProvider.future);
//       await logWellEvent(Supabase.instance.client, {
//         'family_id': familyId,
//         'user_id': userId,
//         'event_type': 'medication_logged',
//         'title': 'Medication Taken',
//         'battery_level': batteryLevel,
//         'description':
//             '${profile?.fullName ?? 'User'} logged ${med.medicationName} (${med.dosage})',
//       });
//
//       if (context.mounted) {
//         ScaffoldMessenger.of(context).showSnackBar(
//           SnackBar(
//             content: Text('✓ Logged ${med.medicationName}. Great job!'),
//             backgroundColor: ShieldColors.safeZoneGreen,
//           ),
//         );
//       }
//     } catch (e) {
//       if (context.mounted) {
//         ScaffoldMessenger.of(
//           context,
//         ).showSnackBar(SnackBar(content: Text('Failed to log dose: $e')));
//       }
//     }
//   }
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final profileAsync = ref.watch(currentUserProfileProvider);
//     final profile = profileAsync.value;
//
//     if (profile == null) return const SizedBox.shrink();
//
//     final medicationsAsync = ref.watch(familyMedicationsProvider);
//     return medicationsAsync.when(
//       data: (meds) {
//         // Find medications assigned to ME that are active
//         final myMeds = meds
//             .where(
//               (m) =>
//                   m.isActive &&
//                   m.assignedTo == profile.userId &&
//                   m.scheduleTimes.isNotEmpty,
//             )
//             .toList();
//
//         if (myMeds.isEmpty) return const SizedBox.shrink();
//
//         return Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           mainAxisSize: MainAxisSize.min,
//           children: myMeds.map((med) {
//             return _ActionItemConsumer(
//               med: med,
//               userId: profile.userId,
//               familyId: profile.familyId,
//               onLogDose: () =>
//                   _logDose(context, ref, med, profile.userId, profile.familyId),
//             );
//           }).toList(),
//         );
//       },
//       loading: () => const SizedBox.shrink(),
//       error: (_, __) => const SizedBox.shrink(),
//     );
//   }
// }
//
// class _ActionItemConsumer extends ConsumerWidget {
//   final Medication med;
//   final String userId;
//   final String familyId;
//   final VoidCallback onLogDose;
//
//   const _ActionItemConsumer({
//     required this.med,
//     required this.userId,
//     required this.familyId,
//     required this.onLogDose,
//   });
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final doseLogsAsync = ref.watch(doseLogsProvider(med.id));
//     final nextDose = med.nextDoseToday;
//     ref.invalidate(doseLogsProvider);
//
//     // We only want to show the prompt if they are scheduled today
//     if (nextDose == null) return const SizedBox.shrink();
//
//     return doseLogsAsync.when(
//       data: (logs) {
//         final now = DateTime.now();
//         // final isTakenToday = logs.any(
//         //   (log) =>
//         //       log.status == 'taken' &&
//         //       log.takenAt != null &&
//         //       log.takenAt!.year == now.year &&
//         //       log.takenAt!.month == now.month &&
//         //       log.takenAt!.day == now.day,
//         // );
//         final medicationLogs = logs
//             .where((log) => log.medicationId == med.id)
//             .toList();
//
//         medicationLogs.sort((a, b) => b.scheduledAt!.compareTo(a.scheduledAt!));
//
//         final latestLog = medicationLogs.isNotEmpty
//             ? medicationLogs.first
//             : null;
//
//         final isTakenToday = latestLog?.status == 'taken';
//         final isMissed = latestLog?.status == 'missed';
//         // print(isMissed);
//         // print("isMissed");
//         // print("isMissed");
//         if (isTakenToday) return const SizedBox.shrink(); // Already taken!
//
//         final diff = nextDose.difference(now).inMinutes;
//         // Prompt them if overdue or if due within the next hour
//         if (diff > 60) return const SizedBox.shrink();
//
//         final isOverdue = diff < 0;
//
//         return Container(
//           margin: const EdgeInsets.only(bottom: 16),
//           padding: const EdgeInsets.all(16),
//           decoration: BoxDecoration(
//             color: isOverdue
//                 ? ShieldColors.alertRed.withValues(alpha: 0.1)
//                 : Colors.amber.shade50,
//             border: Border.all(
//               color: isOverdue ? ShieldColors.alertRed : Colors.amber,
//               width: 1.5,
//             ),
//             borderRadius: ShieldDesign.roundedTwelve,
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Icon(
//                     Icons.warning_amber_rounded,
//                     color: isOverdue
//                         ? ShieldColors.alertRed
//                         : Colors.amber.shade700,
//                   ),
//                   const SizedBox(width: 8),
//                   Text(
//                     'ACTION REQUIRED',
//                     style: TextStyle(
//                       color: isOverdue
//                           ? ShieldColors.alertRed
//                           : Colors.amber.shade800,
//                       fontWeight: FontWeight.bold,
//                       fontSize: 12,
//                       letterSpacing: 1.2,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 12),
//               Text(
//                 'Time to take ${med.medicationName}',
//                 style: const TextStyle(
//                   fontWeight: FontWeight.bold,
//                   fontSize: 16,
//                   color: ShieldColors.textBody,
//                 ),
//               ),
//               Text(
//                 '${med.dosage} · Scheduled for ${DateFormat.jm().format(nextDose)}',
//                 style: const TextStyle(color: Colors.black87),
//               ),
//               if (med.instructions?.isNotEmpty == true)
//                 Padding(
//                   padding: const EdgeInsets.only(top: 4.0),
//                   child: Text(
//                     med.instructions!,
//                     style: const TextStyle(
//                       fontStyle: FontStyle.italic,
//                       color: Colors.black54,
//                     ),
//                   ),
//                 ),
//               const SizedBox(height: 16),
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton.icon(
//                   onPressed: onLogDose,
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: ShieldColors.activeTeal,
//                     foregroundColor: Colors.white,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: ShieldDesign.roundedTwelve,
//                     ),
//                     padding: const EdgeInsets.symmetric(vertical: 12),
//                   ),
//                   icon: const Icon(Icons.check_circle, size: 20),
//                   label: const Text(
//                     'I Took This',
//                     style: TextStyle(fontWeight: FontWeight.bold),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//       loading: () => const SizedBox.shrink(),
//       error: (_, __) => const SizedBox.shrink(),
//     );
//   }
// }
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/medication_provider.dart';
import 'package:intl/intl.dart';

import '../../../main.dart';
import '../../../services/dose_live_activity_service.dart';
import '../../../services/dose_notification_service.dart';

Future<String?> _askReason(BuildContext context) {
  const reasons = [
    'Felt unwell / side effects',
    'Forgot',
    'Ran out of medication',
    'Doctor advised to skip',
    'Other',
  ];
  String? selected;
  final controller = TextEditingController();

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        final isOther = selected == 'Other';
        final canSubmit =
            selected != null && (!isOther || controller.text.trim().isNotEmpty);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Why was it not taken?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: reasons
                    .map(
                      (r) => ChoiceChip(
                        label: Text(r),
                        selected: selected == r,
                        onSelected: (_) => setSheet(() => selected = r),
                      ),
                    )
                    .toList(),
              ),
              if (isOther) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 2,
                  onChanged: (_) => setSheet(() {}),
                  decoration: const InputDecoration(
                    hintText: 'Enter reason',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSubmit
                      ? () => Navigator.pop(
                          ctx,
                          isOther ? controller.text.trim() : selected,
                        )
                      : null,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class PendingActionsCard extends ConsumerStatefulWidget {
  const PendingActionsCard({super.key});

  @override
  ConsumerState<PendingActionsCard> createState() => _PendingActionsCardState();
}

class _PendingActionsCardState extends ConsumerState<PendingActionsCard> {
  @override
  void initState() {
    super.initState();
    DoseNotificationService.instance.onAction = (medId, action) async {
      if (!mounted) return;

      final profile = await ref.read(currentUserProfileProvider.future);
      final meds = await ref.read(familyMedicationsProvider.future);
      if (profile == null) return;

      final med = meds.where((m) => m.id == medId).firstOrNull;
      if (med == null) return;

      if (action == 'log') {
        await _logDose(context, ref, med, profile.userId, profile.familyId);
      } else {
        //   await _logNotTaken(context, ref, med, profile.userId, profile.familyId);
        final reason = await _askReason(context); // see step 3
        if (reason == null || !mounted) return;
        await _logNotTaken(context, ref, med, reason);
      }
    };
  }

  DateTime _nextScheduledDate(Map<String, dynamic> medData) {
    DateTime nextDate = DateTime.parse(medData['scheduled_at']);

    switch (medData['recurrence']) {
      case 'daily':
        nextDate = nextDate.add(const Duration(days: 1));
        break;

      case 'every_other_day':
        nextDate = nextDate.add(const Duration(days: 2));
        break;

      case 'weekly':
        final days = List<int>.from(medData['days_of_week'] ?? [])..sort();

        if (days.isEmpty) {
          nextDate = nextDate.add(const Duration(days: 7));
        } else {
          final currentDay = nextDate.weekday % 7;

          int? found;

          for (final d in days) {
            if (d > currentDay) {
              found = d;
              break;
            }
          }

          found ??= days.first + 7;

          nextDate = nextDate.add(Duration(days: found - currentDay));
        }

        break;

      case 'monthly':
        nextDate = DateTime(
          nextDate.year,
          nextDate.month + 1,
          nextDate.day,
          nextDate.hour,
          nextDate.minute,
        );
        break;

      default:
        break;
    }
    return nextDate;
  }

  @override
  void dispose() {
    DoseNotificationService.instance.onAction = null;
    super.dispose();
  }

  Future<void> _logNotTaken(
    BuildContext context,
    WidgetRef ref,
    Medication med,
    String reason,
  ) async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final supabase = Supabase.instance.client;

      final medData = await supabase
          .from('medications')
          .select('scheduled_at, recurrence, days_of_week')
          .eq('id', med.id)
          .single();

      // 1. If the cron already created a 'missed' row, convert it.
      // final updated = await supabase
      //     .from('dose_logs')
      //     .update({'status': 'not_taken', 'reason': reason})
      //     .eq('medication_id', med.id)
      //     .eq('user_id', med.assignedTo)
      //     .eq('status', 'missed')
      //     .select();
      final updated = await supabase
          .from('dose_logs')
          .update({
            'status': 'not_taken',
            'reason': reason,
            'nag_active': false, // NEW
          })
          .eq('medication_id', med.id)
          .eq('user_id', med.assignedTo)
          .eq('status', 'missed')
          .eq('nag_active', true) // NEW
          .select();
      // 2. Otherwise record this upcoming dose as not taken and advance the schedule.
      if (updated.isEmpty) {
        final scheduledAt = DateTime.parse(
          medData['scheduled_at'].toString(),
        ).toUtc();

        await supabase.from('dose_logs').insert({
          'medication_id': med.id,
          'user_id': med.assignedTo,
          'family_id': profile.familyId,
          'scheduled_at': scheduledAt.toIso8601String(),
          'status': 'not_taken',
          'reason': reason,
        });

        await supabase
            .from('medications')
            .update({
              'scheduled_at': _nextScheduledDate(
                medData,
              ).toUtc().toIso8601String(),
              'reminder_sent': false,
              'reminder_sent_at': null,
            })
            .eq('id', med.id);
      }

      await logWellEvent(supabase, {
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'medication_not_taken',
        'title': 'Medication Not Taken',
        'description':
            '${profile.fullName ?? 'Someone'} did not take ${med.medicationName} ($reason)',
      });

      ref.invalidate(doseLogsProvider(med.id));
      ref.invalidate(allDoseLogsProvider);
      ref.invalidate(familyMedicationsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${med.medicationName} marked as not taken.')),
        );
      }
      await DoseNotificationService.instance.cancelMedication(med.id);
      //await DoseLiveActivityService.instance.end(med.id);
      await DoseLiveActivityService.instance.reschedule(med, takenToday: true);
      // Notify family (same pattern as _logDose)
      final members = await supabase
          .from('family_members')
          .select('user_id')
          .eq('family_id', profile.familyId);

      for (final m in members) {
        final targetUserId = m['user_id'];
        if (targetUserId == profile.userId) continue;
        try {
          await supabase.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "Medications",
              "body":
                  "${profile.fullName ?? 'Someone'}: ${med.medicationName} not taken ($reason)",
              "action": "not_taken",
            },
          );
        } catch (e) {
          debugPrint("Push failed: $e");
        }
      }
    } catch (e) {
      debugPrint('[Medication] Error logging not taken: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error saving reason'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _logDose(
    BuildContext context,
    WidgetRef ref,
    Medication med,
    String userId,
    String familyId,
  ) async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final now = DateTime.now().toUtc();
      int batteryLevel =
          100; // Safe default for simulators and aggressive background iOS policies
      try {
        final battery = Battery();
        batteryLevel = await battery.batteryLevel;
      } catch (e) {
        debugPrint(
          'Battery info not available over isolate, using default: $e',
        );
      }
      final supabase = Supabase.instance.client;

      // Get the CURRENT scheduled dose information
      final medData = await supabase
          .from('medications')
          .select('scheduled_at, recurrence, days_of_week, reminder_sent')
          .eq('id', med.id)
          .single();
      final scheduledAt = DateTime.parse(
        medData['scheduled_at'].toString(),
      ).toUtc();

      final openMissed = await supabase
          .from('dose_logs')
          .select('id')
          .eq('medication_id', med.id)
          .eq('status', 'missed')
          .eq('nag_active', true)
          .isFilter('taken_at', null);

      // Window checks apply only to a normal dose, not a catch-up of a missed one
      if (openMissed.isEmpty) {
        final loggingWindowStart = scheduledAt.subtract(
          const Duration(hours: 1),
        );
        final loggingWindowEnd = scheduledAt.add(const Duration(hours: 1));

        if (now.isBefore(loggingWindowStart)) {
          final difference = loggingWindowStart.difference(now);
          final hours = difference.inHours;
          final minutes = difference.inMinutes % 60;
          final seconds = difference.inSeconds % 60;

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  hours > 0
                      ? 'Medication can be logged in ${hours}h ${minutes}m ${seconds}s.'
                      : minutes > 0
                      ? 'Medication can be logged in ${minutes}m ${seconds}s.'
                      : 'Medication can be logged in ${seconds}s.',
                ),
              ),
            );
          }
          return;
        }

        if (now.isAfter(loggingWindowEnd)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('The medication logging window has expired.'),
              ),
            );
          }
          return;
        }

        final existingLog = await supabase
            .from('dose_logs')
            .select('id, status')
            .eq('medication_id', med.id)
            .eq('scheduled_at', scheduledAt.toIso8601String())
            .eq('status', 'taken')
            .maybeSingle();

        if (existingLog != null) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Medication already recorded.')),
            );
          }
          return;
        }
      }
      await Supabase.instance.client.from('dose_logs').insert({
        'medication_id': med.id,
        'user_id': med.assignedTo,
        'family_id': profile.familyId,
        'scheduled_at': now.toIso8601String(),
        'taken_at': now.toIso8601String(),
        'status': 'taken',
      });

      if (openMissed.isNotEmpty) {
        // Cron already moved scheduled_at. Only stop the nagging.
        await supabase
            .from('dose_logs')
            .update({'nag_active': false})
            .eq('medication_id', med.id)
            .eq('status', 'missed')
            .eq('nag_active', true);
      } else {
        DateTime nextDate = DateTime.parse(medData['scheduled_at']);

        switch (medData['recurrence']) {
          case 'daily':
            nextDate = nextDate.add(const Duration(days: 1));
            break;

          case 'every_other_day':
            nextDate = nextDate.add(const Duration(days: 2));
            break;

          case 'weekly':
            final days = List<int>.from(medData['days_of_week'] ?? [])..sort();

            if (days.isEmpty) {
              nextDate = nextDate.add(const Duration(days: 7));
            } else {
              final currentDay = nextDate.weekday % 7;

              int? found;

              for (final d in days) {
                if (d > currentDay) {
                  found = d;
                  break;
                }
              }

              found ??= days.first + 7;

              nextDate = nextDate.add(Duration(days: found - currentDay));
            }

            break;

          case 'monthly':
            nextDate = DateTime(
              nextDate.year,
              nextDate.month + 1,
              nextDate.day,
              nextDate.hour,
              nextDate.minute,
            );
            break;

          default:
            break;
        }
        await Supabase.instance.client
            .from('medications')
            .update({
              'scheduled_at': nextDate.toUtc().toIso8601String(),

              'reminder_sent': false,
              'reminder_sent_at': null,
            })
            .eq('id', med.id);
      }
      await logWellEvent(Supabase.instance.client, {
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'medication_logged',
        'title': 'Medication Taken',
        'description':
            '${profile.fullName ?? 'Someone'} logged ${med.medicationName} (${med.dosage})',
        'battery_level': batteryLevel,
      });

      // IMPORTANT
      ref.invalidate(allDoseLogsProvider);
      ref.invalidate(familyMedicationsProvider);
      await DoseNotificationService.instance.cancelMedication(med.id);
      //await DoseLiveActivityService.instance.end(med.id);
      await DoseLiveActivityService.instance.reschedule(med, takenToday: true);
      try {
        final meds = await ref.read(familyMedicationsProvider.future);
        await _syncDoseReminders(meds, profile.userId);
      } catch (e) {
        debugPrint('[DoseSync] resync after log failed: $e');
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ ${med.medicationName} dose logged!'),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }

      // Send push
      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id')
          .eq('family_id', profile.familyId);

      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == profile.userId) continue;

        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "Medications",
              "body":
                  "${profile.fullName ?? 'Someone'}: ${med.medicationName} dose logged",
              "action": "log_dose",
            },
          );
        } catch (e) {
          debugPrint("Push failed: $e");
        }
      }
    } catch (e) {
      debugPrint('[Medication] Error logging dose: $e');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging dose'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {}
  }

  Future<void> _syncChain = Future.value();

  // Future<void> _syncDoseReminders(List meds, String userId) async {
  //   final mine = meds
  //       .where((m) => m.isActive && m.assignedTo == userId)
  //       .toList();
  //   await DoseNotificationService.instance.syncMine(
  //     mine,
  //   ); // Android countdown + iOS T-15 alert
  //   await DoseLiveActivityService.instance.sync(mine); // iOS Live Activity
  // }
  Future<void> _syncDoseReminders(List meds, String userId) {
    final mine = meds
        .where((m) => m.isActive && m.assignedTo == userId)
        .toList();
    _syncChain = _syncChain.then((_) async {
      try {
        await DoseNotificationService.instance.syncMine(mine);
        await DoseLiveActivityService.instance.sync(mine);
      } catch (e) {
        debugPrint('[DoseSync] failed: $e');
      }
    });
    return _syncChain;
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.value;

    if (profile == null) return const SizedBox.shrink();

    final medicationsAsync = ref.watch(familyMedicationsProvider);
    return medicationsAsync.when(
      data: (meds) {
        // Find medications assigned to ME that are active
        final myMeds = meds
            .where(
              (m) =>
                  m.isActive &&
                  m.assignedTo == profile.userId &&
                  m.scheduleTimes.isNotEmpty,
            )
            .toList();

        if (myMeds.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: myMeds.map((med) {
            return _ActionItemConsumer(
              med: med,
              userId: profile.userId,
              familyId: profile.familyId,
              onNotTaken: (reason) => _logNotTaken(context, ref, med, reason),

              onLogDose: () =>
                  _logDose(context, ref, med, profile.userId, profile.familyId),
            );
          }).toList(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

// class _ActionItemConsumer extends ConsumerWidget {
//   final Medication med;
//   final String userId;
//   final String familyId;
//   final VoidCallback onLogDose;
//
//   const _ActionItemConsumer({
//     required this.med,
//     required this.userId,
//     required this.familyId,
//     required this.onLogDose,
//   });
//
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final doseLogsAsync = ref.watch(doseLogsProvider(med.id));
//     final nextDose = med.nextDoseToday;
//     ref.invalidate(doseLogsProvider);
//
//     // We only want to show the prompt if they are scheduled today
//     if (nextDose == null) return const SizedBox.shrink();
//
//     return doseLogsAsync.when(
//       data: (logs) {
//         final now = DateTime.now();
//         // final isTakenToday = logs.any(
//         //   (log) =>
//         //       log.status == 'taken' &&
//         //       log.takenAt != null &&
//         //       log.takenAt!.year == now.year &&
//         //       log.takenAt!.month == now.month &&
//         //       log.takenAt!.day == now.day,
//         // );
//         final medicationLogs = logs
//             .where((log) => log.medicationId == med.id)
//             .toList();
//
//         medicationLogs.sort((a, b) => b.scheduledAt!.compareTo(a.scheduledAt!));
//
//         final latestLog = medicationLogs.isNotEmpty
//             ? medicationLogs.first
//             : null;
//
//         final isTakenToday = latestLog?.status == 'taken';
//         final isMissed = latestLog?.status == 'missed';
//         // print(isMissed);
//         // print("isMissed");
//         // print("isMissed");
//         if (isTakenToday) return const SizedBox.shrink(); // Already taken!
//
//         final diff = nextDose.difference(now).inMinutes;
//         // Prompt them if overdue or if due within the next hour
//         if (diff > 60) return const SizedBox.shrink();
//
//         final isOverdue = diff < 0;
//
//         return Container(
//           margin: const EdgeInsets.only(bottom: 16),
//           padding: const EdgeInsets.all(16),
//           decoration: BoxDecoration(
//             color: isOverdue
//                 ? ShieldColors.alertRed.withValues(alpha: 0.1)
//                 : Colors.amber.shade50,
//             border: Border.all(
//               color: isOverdue ? ShieldColors.alertRed : Colors.amber,
//               width: 1.5,
//             ),
//             borderRadius: ShieldDesign.roundedTwelve,
//           ),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Row(
//                 children: [
//                   Icon(
//                     Icons.warning_amber_rounded,
//                     color: isOverdue
//                         ? ShieldColors.alertRed
//                         : Colors.amber.shade700,
//                   ),
//                   const SizedBox(width: 8),
//                   Text(
//                     'ACTION REQUIRED',
//                     style: TextStyle(
//                       color: isOverdue
//                           ? ShieldColors.alertRed
//                           : Colors.amber.shade800,
//                       fontWeight: FontWeight.bold,
//                       fontSize: 12,
//                       letterSpacing: 1.2,
//                     ),
//                   ),
//                 ],
//               ),
//               const SizedBox(height: 12),
//               Text(
//                 'Time to take ${med.medicationName}',
//                 style: const TextStyle(
//                   fontWeight: FontWeight.bold,
//                   fontSize: 16,
//                   color: ShieldColors.textBody,
//                 ),
//               ),
//               Text(
//                 '${med.dosage} · Scheduled for ${DateFormat.jm().format(nextDose)}',
//                 style: const TextStyle(color: Colors.black87),
//               ),
//               if (med.instructions?.isNotEmpty == true)
//                 Padding(
//                   padding: const EdgeInsets.only(top: 4.0),
//                   child: Text(
//                     med.instructions!,
//                     style: const TextStyle(
//                       fontStyle: FontStyle.italic,
//                       color: Colors.black54,
//                     ),
//                   ),
//                 ),
//               const SizedBox(height: 16),
//               SizedBox(
//                 width: double.infinity,
//                 child: ElevatedButton.icon(
//                   onPressed: onLogDose,
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: ShieldColors.activeTeal,
//                     foregroundColor: Colors.white,
//                     shape: RoundedRectangleBorder(
//                       borderRadius: ShieldDesign.roundedTwelve,
//                     ),
//                     padding: const EdgeInsets.symmetric(vertical: 12),
//                   ),
//                   icon: const Icon(Icons.check_circle, size: 20),
//                   label: const Text(
//                     'I Took This',
//                     style: TextStyle(fontWeight: FontWeight.bold),
//                   ),
//                 ),
//               ),
//             ],
//           ),
//         );
//       },
//       loading: () => const SizedBox.shrink(),
//       error: (_, __) => const SizedBox.shrink(),
//     );
//   }
// }

class _ActionItemConsumer extends ConsumerStatefulWidget {
  final Medication med;
  final String userId;
  final String familyId;
  final Future<void> Function() onLogDose;
  final Future<void> Function(String reason) onNotTaken;

  const _ActionItemConsumer({
    super.key,
    required this.med,
    required this.userId,
    required this.familyId,
    required this.onLogDose,
    required this.onNotTaken,
  });

  @override
  ConsumerState<_ActionItemConsumer> createState() =>
      _ActionItemConsumerState();
}

class _ActionItemConsumerState extends ConsumerState<_ActionItemConsumer> {
  bool _isLogging = false;
  bool _isSkipping = false;

  Future<void> _handleNotTaken() async {
    if (_isLogging || _isSkipping) return;

    final reason = await _askReason(context);
    if (reason == null || !mounted) return;

    setState(() => _isSkipping = true);
    try {
      await widget.onNotTaken(reason);
    } finally {
      if (mounted) setState(() => _isSkipping = false);
    }
  }

  Future<void> _handleLogDose() async {
    if (_isLogging) return;

    setState(() => _isLogging = true);

    try {
      await widget.onLogDose();
    } finally {
      if (mounted) {
        setState(() => _isLogging = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.med;
    final userId = widget.userId;
    final familyId = widget.familyId;
    final doseLogsAsync = ref.watch(doseLogsProvider(med.id));

    // Do not invalidate providers inside build().
    return doseLogsAsync.when(
      data: (logs) {
        final now = DateTime.now();
        final startDate = med.startDate ?? now;

        bool isSameDay(DateTime? date) {
          return date != null &&
              date.year == now.year &&
              date.month == now.month &&
              date.day == now.day;
        }

        final medicationLogs = logs
            .where((log) => log.medicationId == med.id)
            .toList();

        // Check whether a dose was missed today.
        // final missedToday = medicationLogs
        //     .where(
        //       (log) => log.status == 'missed' && isSameDay(log.scheduledAt),
        //     )
        //     .toList();
        //
        // missedToday.sort((a, b) {
        //   final aTime = a.scheduledAt;
        //   final bTime = b.scheduledAt;
        //
        //   if (aTime == null) return 1;
        //   if (bTime == null) return -1;
        //
        //   return bTime.compareTo(aTime);
        // });
        final takenAfter = medicationLogs
            .where((l) => l.status == 'taken' && l.takenAt != null)
            .toList();

        final missedToday = medicationLogs.where((l) {
          if (l.status != 'missed' || l.scheduledAt == null) return false;
          final due = l.scheduledAt!;
          // still pending if nothing was taken at/after the due time
          return !takenAfter.any((t) => !t.takenAt!.isBefore(due));
        }).toList()..sort((a, b) => b.scheduledAt!.compareTo(a.scheduledAt!));

        final isMissedToday = missedToday.isNotEmpty;
        // final takenAfter = medicationLogs
        //     .where((l) => l.status == 'taken' && l.takenAt != null)
        //     .toList();
        //
        // final isMissedToday = missedToday.isNotEmpty;

        // Match the recurrence-based taken check.
        final takenLogs = medicationLogs.where(
          (log) => log.status == 'taken' && log.takenAt != null,
        );

        bool isTakenToday = false;

        switch (med.recurrence) {
          case 'daily':
            isTakenToday = takenLogs.any((log) => isSameDay(log.takenAt));
            break;

          case 'every_other_day':
            final today = DateTime(now.year, now.month, now.day);
            final start = DateTime(
              startDate.year,
              startDate.month,
              startDate.day,
            );

            final diffDays = today.difference(start).inDays;
            final shouldTakeToday = diffDays >= 0 && diffDays % 2 == 0;

            isTakenToday =
                shouldTakeToday &&
                takenLogs.any((log) => isSameDay(log.takenAt));
            break;

          case 'weekly':
            isTakenToday = takenLogs.any((log) => isSameDay(log.takenAt));
            break;

          case 'monthly':
            isTakenToday = takenLogs.any((log) => isSameDay(log.takenAt));
            break;

          default:
            isTakenToday = takenLogs.any((log) => isSameDay(log.takenAt));
        }

        // // A taken dose hides today's reminder.
        // if (isTakenToday) {
        //   return const SizedBox.shrink();
        // }
        //
        // // Get the next scheduled dose.
        // final nextDose = med.nextDoseToday;
        //
        // // Keep today's missed dose visible, even when the next
        // // regular daily dose is tomorrow.
        // if (nextDose == null && !isMissedToday) {
        //   return const SizedBox.shrink();
        // }
        //
        // final DateTime displayDoseTime = isMissedToday
        //     ? missedToday.first.scheduledAt!
        //     : nextDose!;
        //
        // final diff = displayDoseTime.difference(now).inMinutes;
        //
        // // Show missed doses regardless of the next scheduled dose.
        // // Otherwise, show overdue doses or doses due within 24 hours.
        // if (!isMissedToday && diff > 1440) {
        //   return const SizedBox.shrink();
        // }
        //
        // final isOverdue = isMissedToday || diff < 0;
        // if (isTakenToday) {
        //   return const SizedBox.shrink();
        // }
        if (isTakenToday && !isMissedToday) {
          return const SizedBox.shrink();
        }
        // final nextDose = med.nextDoseToday;
        //
        // // Keep today's missed dose visible.
        // if (nextDose == null && !isMissedToday) {
        //   return const SizedBox.shrink();
        // }
        //
        // final DateTime displayDoseTime = isMissedToday
        //     ? missedToday.first.scheduledAt!
        //     : nextDose!;
        //
        // final diff = displayDoseTime.difference(now).inMinutes;
        //
        // // Show from 1 hour before the scheduled time until logged.
        // if (!isMissedToday && diff > 60) {
        //   return const SizedBox.shrink();
        // }
        //
        // final isOverdue = isMissedToday || diff <= 0;
        const graceWindow = Duration(minutes: 5);
        DateTime? graceDose = med.nextDoseToday;

        // Dose that was due within the last 5 min and isn't logged/missed yet
        if (graceDose == null && med.scheduledAt != null) {
          final due = med.scheduledAt!.toLocal();
          if (!now.isBefore(due) && now.isBefore(due.add(graceWindow))) {
            graceDose = due;
          }
        } // see section 2

        if (graceDose == null && !isMissedToday) {
          return const SizedBox.shrink();
        }

        final DateTime displayDoseTime = isMissedToday
            ? missedToday.first.scheduledAt!
            : graceDose!;

        final diff = displayDoseTime.difference(now).inMinutes;

        // Hide only if it's more than 1h away, or it's past the grace window
        // and no missed row exists (cron will create it)
        if (!isMissedToday && diff > 60) {
          return const SizedBox.shrink();
        }

        final isOverdue = isMissedToday || diff <= 0;
        final inGrace =
            isOverdue &&
            !isMissedToday &&
            now.isBefore(displayDoseTime.add(graceWindow));
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isOverdue
                ? ShieldColors.alertRed.withValues(alpha: 0.1)
                : Colors.amber.shade50,
            border: Border.all(
              color: isOverdue ? ShieldColors.alertRed : Colors.amber,
              width: 1.5,
            ),
            borderRadius: ShieldDesign.roundedTwelve,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: isOverdue
                        ? ShieldColors.alertRed
                        : Colors.amber.shade700,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isMissedToday ? 'MISSED MEDICATION' : 'ACTION REQUIRED',
                    style: TextStyle(
                      color: isOverdue
                          ? ShieldColors.alertRed
                          : Colors.amber.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isMissedToday
                    ? 'You missed ${med.medicationName} today'
                    : 'Time to take ${med.medicationName}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: ShieldColors.textBody,
                ),
              ),
              Text(
                '${med.dosage} · Scheduled for '
                '${DateFormat.jm().format(displayDoseTime.toLocal())}',
                style: const TextStyle(color: Colors.black87),
              ),
              if (med.instructions?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    med.instructions!,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.black54,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  // onPressed: _isLogging ? null : _handleLogDose,
                  onPressed: (_isLogging || _isSkipping)
                      ? null
                      : _handleLogDose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShieldColors.activeTeal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: ShieldColors.activeTeal.withValues(
                      alpha: 0.7,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _isLogging
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(Icons.check_circle, size: 20),
                  label: Text(
                    _isLogging ? 'Logging...' : 'I Took This',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: (_isLogging || _isSkipping)
                      ? null
                      : _handleNotTaken,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: ShieldColors.alertRed,
                    side: const BorderSide(color: ShieldColors.alertRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: _isSkipping
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cancel_outlined, size: 20),
                  label: Text(
                    _isSkipping ? 'Saving...' : 'Skip',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
