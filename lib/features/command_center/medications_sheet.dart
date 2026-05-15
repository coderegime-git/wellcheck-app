import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/medication_provider.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/features/command_center/add_medication_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class MedicationsSheet extends ConsumerStatefulWidget {
  bool? fromLeader = false;

  MedicationsSheet({super.key, this.fromLeader});

  @override
  ConsumerState<MedicationsSheet> createState() => _MedicationsSheetState();
}

class _MedicationsSheetState extends ConsumerState<MedicationsSheet> {
  final FlutterTts _flutterTts = FlutterTts();
  bool _isPlaying = false;
  String? _loggingMedicationId;

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.45);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isPlaying = false);
    });
    ref.invalidate(familyMedicationsProvider);
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

  Future<void> _speak(String title, String? instructions) async {
    if (_isPlaying) {
      await _flutterTts.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    if (mounted) setState(() => _isPlaying = true);
    final text =
        "Instructions for $title. ${instructions ?? 'No additional instructions provided.'}";
    await _flutterTts.speak(text);
  }

  // Future<void> _logDose(Medication med) async {
  //   try {
  //     final profile = await ref.read(currentUserProfileProvider.future);
  //     if (profile == null) return;
  //
  //     final now = DateTime.now().toUtc();
  //
  //     // Log to dose_logs
  //     await Supabase.instance.client.from('dose_logs').insert({
  //       'medication_id': med.id,
  //       'user_id': med.assignedTo, // The person who takes it
  //       'family_id': profile.familyId,
  //       'scheduled_at': now.toIso8601String(),
  //       'taken_at': now.toIso8601String(),
  //       'status': 'taken',
  //     });
  //
  //     // Also log to well_events for the family feed
  //     await Supabase.instance.client.from('well_events').insert({
  //       'family_id': profile.familyId,
  //       'user_id': profile.userId,
  //       'event_type': 'medication_logged',
  //       'title': 'Medication Taken',
  //       'description':
  //           '${profile.fullName ?? 'Someone'} logged ${med.medicationName} (${med.dosage})',
  //     });
  //
  //     if (mounted) {
  //       ref.refresh(familyMedicationsProvider);
  //       ref.invalidate(familyMedicationsProvider);
  //
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('✓ ${med.medicationName} dose logged!'),
  //           backgroundColor: ShieldColors.safeZoneGreen,
  //         ),
  //       );
  //
  //     }
  //   } catch (e) {
  //     debugPrint('[Medication] Error logging dose: $e');
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Error logging dose: $e'),
  //           backgroundColor: Colors.red,
  //           duration: const Duration(seconds: 6),
  //         ),
  //       );
  //     }
  //   }finally{
  //     final profile = await ref.read(currentUserProfileProvider.future);
  //     if (profile == null) throw Exception('No profile');
  //
  //     final members = await Supabase.instance.client
  //         .from('family_members')
  //         .select('user_id')
  //         .eq('family_id', profile.familyId);
  //
  //     // 3. Send push
  //     for (final m in members) {
  //       final targetUserId = m['user_id'];
  //
  //       if (targetUserId == profile.userId) continue;
  //
  //       try {
  //         await Supabase.instance.client.functions.invoke(
  //           'push-router',
  //           body: {
  //             "target_user_id": targetUserId,
  //             "title": "Medications",
  //             "body":
  //             "${profile.fullName ?? 'Someone'}:${med.medicationName}  dose logged",
  //             "action": "log_dose",
  //           },
  //         );
  //       } catch (e) {
  //         print("Push failed: $e");
  //       }
  //     }
  //   }
  // }

  Future<void> _logDose(Medication med) async {
    if (_loggingMedicationId != null) return;

    setState(() {
      _loggingMedicationId = med.id;
    });

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

      await Supabase.instance.client.from('dose_logs').insert({
        'medication_id': med.id,
        'user_id': med.assignedTo,
        'family_id': profile.familyId,
        'scheduled_at': now.toIso8601String(),
        'taken_at': now.toIso8601String(),
        'status': 'taken',
      });
      final medData = await Supabase.instance.client
          .from('medications')
          .select('scheduled_at, recurrence, days_of_week')
          .eq('id', med.id)
          .single();

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
      await Supabase.instance.client.from('well_events').insert({
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

      if (mounted) {
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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging dose: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loggingMedicationId = null;
        });
      }
    }
  }

  Future<void> _deleteMedication(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Medication'),
        content: const Text(
          'Are you sure you want to delete this medication? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: ShieldColors.alertRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await Supabase.instance.client.from('medications').delete().eq('id', id);
      ref.invalidate(allDoseLogsProvider);
      ref.invalidate(familyMedicationsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to delete: $e')));
      }
    }
  }

  Color _doseStatusColor(Medication med) {
    final next = med.nextDoseToday;
    if (next == null) return Colors.grey;
    final diff = next.difference(DateTime.now()).inMinutes;
    if (diff < 0) return ShieldColors.urgentRed; // Overdue
    if (diff < 30) return Colors.amber.shade700; // Due soon
    return ShieldColors.safeZoneGreen; // On track
  }

  String _nextDoseLabel(Medication med) {
    if (med.scheduleTimes.isEmpty) return med.frequency;
    final next = med.nextDoseToday;
    if (next == null) {
      return 'Done for today';
    }
    final diff = next.difference(DateTime.now()).inMinutes;
    if (diff < 0) {
      return 'Overdue by ${(-diff)} min';
    }
    if (diff < 60) {
      return 'Due in $diff min';
    }
    return 'Next: ${DateFormat.jm().format(next)}';
  }

  @override
  Widget build(BuildContext context) {
    final medicationsAsync = ref.watch(familyMedicationsProvider);
    final profile = ref.watch(currentUserProfileProvider);
    print(profile.value!.role);
    print("sheeeeet");
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            children: [
              Text(
                'Medications',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: ShieldColors.textBody,
                ),
              ),
              Spacer(),
              //
              if (widget.fromLeader == true)
                IconButton(
                  onPressed: () async {
                    await showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,

                      backgroundColor: Colors.transparent,
                      builder: (context) => const AddMedicationSheet(),
                    );
                    ref.refresh(familyMedicationsProvider);
                  },
                  icon: const Icon(
                    Icons.add_circle,
                    color: ShieldColors.activeTeal,
                    size: 32,
                  ),
                ),
              SizedBox(width: 10),
              GestureDetector(
                onTap: () async {
                  Navigator.of(context).pop();
                },
                child: Container(
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.shade400,
                        offset: Offset(0, 0),
                        blurRadius: 3,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.black, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Content
          Expanded(
            child: medicationsAsync.when(
              data: (meds) {
                if (meds.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.fromLeader == true)
                          Icon(
                            Icons.medical_services_outlined,
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                        const SizedBox(height: 16),
                        const Text(
                          'No medications scheduled yet.',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        if (widget.fromLeader == true)
                          const Text(
                            'Tap + to add a medication with reminders.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                      ],
                    ),
                  );
                }

                // Separate active vs inactive
                final role = profile.value?.role;

                final isLeaderOrMonitor = role == "leader" || role == "monitor";

                final active = isLeaderOrMonitor
                    ? meds.where((m) => m.isActive).toList()
                    : meds
                          .where(
                            (m) =>
                                m.isActive &&
                                m.assignedTo == profile.value?.userId,
                          )
                          .toList();

                final inactive = isLeaderOrMonitor
                    ? meds.where((m) => !m.isActive).toList()
                    : meds
                          .where(
                            (m) =>
                                !m.isActive &&
                                m.assignedTo == profile.value?.userId,
                          )
                          .toList();
                return ListView(
                  children: [
                    // Today's schedule summary
                    if (active.any((m) => m.scheduleTimes.isNotEmpty))
                      _todaysSummaryCard(active),

                    ...active.map(
                      (med) => MedicationCard(
                        isLeader: widget.fromLeader,
                        isLogging: _loggingMedicationId == med.id,
                        med: med,
                        onDelete: () => _deleteMedication(med.id),
                        onLogDose: () => _logDose(med),
                        isPlaying: _isPlaying,
                        onEdit: () async {
                          await showModalBottomSheet(
                            context: context,
                            useSafeArea: true,

                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) =>
                                AddMedicationSheet(existingMedication: med),
                          );
                          ref.invalidate(allDoseLogsProvider);
                          ref.invalidate(familyMedicationsProvider);
                          ref.refresh(familyMedicationsProvider);
                        },
                        onSpeak: () =>
                            _speak(med.medicationName, med.instructions),
                      ),
                    ),

                    if (inactive.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'Inactive',
                          style: TextStyle(
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      ...inactive.map(
                        (med) => MedicationCard(
                          isLeader: widget.fromLeader,
                          isLogging: _loggingMedicationId == med.id,
                          med: med,
                          onDelete: () => _deleteMedication(med.id),
                          onLogDose: () => _logDose(med),
                          isPlaying: _isPlaying,
                          onEdit: () async {
                            await showModalBottomSheet(
                              context: context,
                              useSafeArea: true,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) =>
                                  AddMedicationSheet(existingMedication: med),
                            );
                            ref.refresh(familyMedicationsProvider);
                            ref.invalidate(allDoseLogsProvider);
                            ref.invalidate(familyMedicationsProvider);
                          },
                          onSpeak: () =>
                              _speak(med.medicationName, med.instructions),
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _todaysSummaryCard(List<Medication> active) {
    final totalDoses = active.fold<int>(
      0,
      (sum, m) => sum + m.scheduleTimes.length,
    );
    final upcoming = active.where((m) => m.nextDoseToday != null).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF007F80), Color(0xFF059669)],
        ),
        borderRadius: ShieldDesign.roundedTwelve,
      ),
      child: Row(
        children: [
          const Icon(Icons.today, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Today's Schedule",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Text(
                '$totalDoses doses · $upcoming remaining',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MedicationCard extends ConsumerWidget {
  final Medication med;
  final VoidCallback onDelete;
  final VoidCallback onLogDose;
  final bool isPlaying;
  final VoidCallback onSpeak;
  final VoidCallback? onEdit;
  final bool isLogging;
  bool? isLeader = false;

  MedicationCard({
    super.key,
    required this.med,
    required this.onDelete,
    required this.onLogDose,
    required this.isPlaying,
    required this.onSpeak,
    required this.isLogging,
    this.onEdit,
    required this.isLeader,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allLogsAsync = ref.watch(allDoseLogsProvider);
    //final doseLogsAsync = ref.watch(doseLogsProvider(med.id));

    // Determine if taken today
    //bool isTakenToday = false;
    // allLogsAsync.whenData((logs) {
    //   final now = DateTime.now();
    //   isTakenToday = logs.any(
    //     (log) =>
    //         log.medicationId == med.id &&
    //         log.status == 'taken' &&
    //         log.takenAt != null &&
    //         log.takenAt!.year == now.year &&
    //         log.takenAt!.month == now.month &&
    //         log.takenAt!.day == now.day,
    //   );
    // });
    final logs = allLogsAsync.value ?? [];

    final now = DateTime.now();
    final isTakenToday = logs.any(
      (log) =>
          log.medicationId == med.id &&
          log.status == 'taken' &&
          log.takenAt != null &&
          log.takenAt!.year == now.year &&
          log.takenAt!.month == now.month &&
          log.takenAt!.day == now.day,
    );
    final nextDose = med.nextDoseToday;
    final statusColor = isTakenToday
        ? ShieldColors.safeZoneGreen
        : nextDose == null
        ? Colors.grey
        : nextDose.difference(DateTime.now()).inMinutes < 0
        ? ShieldColors.urgentRed
        : Colors.amber.shade700;

    final nextLabel = isTakenToday
        ? 'Taken Today'
        : med.scheduleTimes.isEmpty
        ? med.frequency
        : nextDose == null
        ? 'Done for today'
        : nextDose.difference(DateTime.now()).inMinutes < 0
        ? 'Overdue'
        : 'Next: ${DateFormat.jm().format(nextDose)}';

    return Dismissible(
      key: Key(med.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: ShieldColors.alertRed,
          borderRadius: ShieldDesign.roundedTwelve,
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: ShieldDesign.roundedTwelve),
        elevation: 1,

        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  Expanded(
                    child: Text(
                      med.medicationName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: med.isActive
                            ? ShieldColors.textBody
                            : Colors.grey,
                      ),
                    ),
                  ),

                  if (med.scheduleTimes.isNotEmpty || isTakenToday)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        nextLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  if (isLeader == true)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      onSelected: (value) {
                        if (value == 'edit') {
                          onEdit?.call();
                        } else if (value == 'delete') {
                          onDelete?.call();
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(
                                Icons.edit_outlined,
                                color: ShieldColors.activeTeal,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text('Edit'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete,
                                color: ShieldColors.alertRed,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: ShieldColors.alertRed),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Dosage + schedule
              Text(
                '${med.dosage} · ${med.scheduleSummary}',
                style: const TextStyle(color: Colors.black87, fontSize: 14),
              ),

              // Date range
              if (med.startDate != null) ...[
                const SizedBox(height: 4),
                Text(
                  'From ${DateFormat('MMM d').format(med.startDate!)}${med.endDate != null ? ' to ${DateFormat('MMM d').format(med.endDate!)}' : ' · Ongoing'}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],

              // Instructions
              if (med.instructions != null && med.instructions!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        med.instructions!,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontStyle: FontStyle.italic,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        isPlaying ? Icons.stop_circle : Icons.volume_up,
                        color: ShieldColors.activeTeal,
                      ),
                      onPressed: onSpeak,
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),

              // Log Dose button
              // if (med.isActive && !isTakenToday)
              //   SizedBox(
              //     width: double.infinity,
              //     child: ElevatedButton.icon(
              //       onPressed: onLogDose,
              //       style: ElevatedButton.styleFrom(
              //         backgroundColor: ShieldColors.activeTeal,
              //         foregroundColor: Colors.white,
              //         shape: RoundedRectangleBorder(
              //           borderRadius: ShieldDesign.roundedTwelve,
              //         ),
              //         padding: const EdgeInsets.symmetric(vertical: 12),
              //       ),
              //       icon: const Icon(Icons.check_circle, size: 20),
              //       label: const Text(
              //         'Log Dose Taken',
              //         style: TextStyle(fontWeight: FontWeight.bold),
              //       ),
              //     ),
              //   ),
              if (med.isActive && !isTakenToday && isLeader == true)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: isLogging ? null : onLogDose,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ShieldColors.activeTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: isLogging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle, size: 20),
                    label: Text(
                      isLogging ? 'Logging...' : 'Log Dose Taken',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
