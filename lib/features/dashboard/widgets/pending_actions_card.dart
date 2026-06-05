import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/medication_provider.dart';
import 'package:intl/intl.dart';

class PendingActionsCard extends ConsumerWidget {
  const PendingActionsCard({super.key});

  Future<void> _logDose(
    BuildContext context,
    WidgetRef ref,
    Medication med,
    String userId,
    String familyId,
  ) async {
    final now = DateTime.now().toUtc();
    try {
      await Supabase.instance.client.from('dose_logs').insert({
        'medication_id': med.id,
        'user_id': userId,
        'family_id': familyId,
        'scheduled_at': now.toIso8601String(),
        'taken_at': now.toIso8601String(),
        'status': 'taken',
      });
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
      final profile = await ref.read(currentUserProfileProvider.future);
      await Supabase.instance.client.from('well_events').insert({
        'family_id': familyId,
        'user_id': userId,
        'event_type': 'medication_logged',
        'title': 'Medication Taken',
        'battery_level': batteryLevel,
        'description':
            '${profile?.fullName ?? 'User'} logged ${med.medicationName} (${med.dosage})',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Logged ${med.medicationName}. Great job!'),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to log dose: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

class _ActionItemConsumer extends ConsumerWidget {
  final Medication med;
  final String userId;
  final String familyId;
  final VoidCallback onLogDose;

  const _ActionItemConsumer({
    required this.med,
    required this.userId,
    required this.familyId,
    required this.onLogDose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doseLogsAsync = ref.watch(doseLogsProvider(med.id));
    final nextDose = med.nextDoseToday;
    ref.invalidate(doseLogsProvider);

    // We only want to show the prompt if they are scheduled today
    if (nextDose == null) return const SizedBox.shrink();

    return doseLogsAsync.when(
      data: (logs) {
        final now = DateTime.now();
        // final isTakenToday = logs.any(
        //   (log) =>
        //       log.status == 'taken' &&
        //       log.takenAt != null &&
        //       log.takenAt!.year == now.year &&
        //       log.takenAt!.month == now.month &&
        //       log.takenAt!.day == now.day,
        // );
        final medicationLogs = logs
            .where((log) => log.medicationId == med.id)
            .toList();

        medicationLogs.sort((a, b) => b.scheduledAt!.compareTo(a.scheduledAt!));

        final latestLog = medicationLogs.isNotEmpty
            ? medicationLogs.first
            : null;

        final isTakenToday = latestLog?.status == 'taken';
        final isMissed = latestLog?.status == 'missed';
        print(isMissed);
        print("isMissed");
        print("isMissed");
        if (isTakenToday) return const SizedBox.shrink(); // Already taken!

        final diff = nextDose.difference(now).inMinutes;
        // Prompt them if overdue or if due within the next hour
        if (diff > 60) return const SizedBox.shrink();

        final isOverdue = diff < 0;

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
                    'ACTION REQUIRED',
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
                'Time to take ${med.medicationName}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: ShieldColors.textBody,
                ),
              ),
              Text(
                '${med.dosage} · Scheduled for ${DateFormat.jm().format(nextDose)}',
                style: const TextStyle(color: Colors.black87),
              ),
              if (med.instructions?.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
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
                  onPressed: onLogDose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ShieldColors.activeTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.check_circle, size: 20),
                  label: const Text(
                    'I Took This',
                    style: TextStyle(fontWeight: FontWeight.bold),
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
